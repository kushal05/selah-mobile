import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/chord_transposition.dart';
import '../../../../core/sync/models/song_model.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

String _transposeKey(String songId) => 'song_transpose_$songId';

/// Song detail screen with lyrics, structured chord view, and transposition controls.
/// Supports:
/// - Lyrics-only mode
/// - Chord view with structured chord lines aligned above lyrics
/// - Legacy inline [chord] rendering as fallback
/// - Transpose +/- by semitone (render-time only, never mutates stored data)
class SongDetailScreen extends ConsumerStatefulWidget {
  final String songId;

  const SongDetailScreen({super.key, required this.songId});

  @override
  ConsumerState<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends ConsumerState<SongDetailScreen> {
  static final _chordRegex = RegExp(r'\[([^\]]+)\]');

  bool _showChords = false;
  bool _isFullscreen = false;

  /// Transposition offset in semitones. Persisted per-song via SharedPreferences.
  int _transposeSteps = 0;

  @override
  void initState() {
    super.initState();
    // Load persisted transposition for this song (post-frame so ref is ready).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prefs = ref.read(sharedPreferencesProvider);
      final saved = prefs.getInt(_transposeKey(widget.songId)) ?? 0;
      if (saved != 0) setState(() => _transposeSteps = saved);
    });
  }

  void _setTransposeSteps(int steps) {
    setState(() => _transposeSteps = steps);
    final prefs = ref.read(sharedPreferencesProvider);
    if (steps == 0) {
      prefs.remove(_transposeKey(widget.songId));
    } else {
      prefs.setInt(_transposeKey(widget.songId), steps);
    }
  }

  @override
  Widget build(BuildContext context) {
    final songAsync = ref.watch(songByIdProvider(widget.songId));

    return songAsync.when(
      loading: () => const Scaffold(body: DetailPageSkeleton()),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $error')),
      ),
      data: (song) {
        if (song == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Song not found')),
          );
        }

        return Scaffold(
          appBar: _isFullscreen
              ? null
              : AppBar(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => context.pop(),
                  ),
                  title: Text(song.title, style: AppTheme.headingMedium),
                  actions: [
                    IconButton(
                      icon: Icon(
                        song.isFavorite
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: song.isFavorite ? AppTheme.error : null,
                      ),
                      onPressed: () => _toggleFavorite(),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) => _handleMenuAction(value, song.id),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: AppTheme.iconBase),
                              SizedBox(width: AppTheme.spacing12),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Row(
                            children: [
                              Icon(Icons.share, size: AppTheme.iconBase),
                              SizedBox(width: AppTheme.spacing12),
                              Text('Share Lyrics'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: Row(
                            children: [
                              Icon(Icons.copy, size: AppTheme.iconBase),
                              SizedBox(width: AppTheme.spacing12),
                              Text('Duplicate'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete,
                                size: AppTheme.iconBase,
                                color: AppTheme.error,
                              ),
                              SizedBox(width: AppTheme.spacing12),
                              Text(
                                'Move to Trash',
                                style: TextStyle(color: AppTheme.error),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          body: GestureDetector(
            onTap: () {
              if (_isFullscreen) {
                setState(() => _isFullscreen = false);
              }
            },
            child: SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Mode toggle, transpose bar, and fullscreen button
                      if (!_isFullscreen) _buildControlBar(song),

                      // Metadata chips
                      if (!_isFullscreen) _buildMetadataRow(song),

                      // Transpose control bar (shown in chord mode)
                      if (_showChords && song.hasChords && !_isFullscreen)
                        _buildTransposeBar(song),

                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            _isFullscreen
                                ? AppTheme.spacing24
                                : AppTheme.spacing16,
                            _isFullscreen
                                ? 56.0
                                : AppTheme.spacing16,
                            _isFullscreen
                                ? AppTheme.spacing24
                                : AppTheme.spacing16,
                            _isFullscreen
                                ? AppTheme.spacing24
                                : AppTheme.spacing16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _showChords && song.hasChords
                                  ? _buildChordContent(song)
                                  : _buildLyricsView(song.lyrics),
                              if (song.notes.trim().isNotEmpty &&
                                  !_isFullscreen) ...[
                                const SizedBox(height: AppTheme.spacing24),
                                _buildNotesSection(song.notes),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isFullscreen)
                    Positioned(
                      top: AppTheme.spacing8,
                      right: AppTheme.spacing8,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Exit full screen',
                          onPressed: () =>
                              setState(() => _isFullscreen = false),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlBar(SongModel song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing16,
        AppTheme.spacing8,
        AppTheme.spacing16,
        AppTheme.spacing8,
      ),
      child: Row(
        children: [
          if (song.hasChords)
            Container(
              decoration: BoxDecoration(
                color: AppTheme.gray100,
                borderRadius: AppTheme.borderRadiusMD,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ModeButton(
                    label: 'Lyrics',
                    isSelected: !_showChords,
                    onTap: () => setState(() => _showChords = false),
                  ),
                  _ModeButton(
                    label: 'Chords',
                    isSelected: _showChords,
                    onTap: () => setState(() => _showChords = true),
                  ),
                ],
              ),
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: () => setState(() => _isFullscreen = true),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(SongModel song) {
    // Compute the displayed key: original scale transposed by _transposeSteps
    final displayedKey = _getDisplayedKey(song);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing16,
        0,
        AppTheme.spacing16,
        AppTheme.spacing8,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (displayedKey.isNotEmpty)
              _MetadataChip(icon: Icons.piano, label: 'Key: $displayedKey'),
            if (displayedKey.isNotEmpty)
              const SizedBox(width: AppTheme.spacing8),
            _MetadataChip(icon: Icons.language, label: song.language),
            if (song.book != null && song.book!.isNotEmpty) ...[
              const SizedBox(width: AppTheme.spacing8),
              _MetadataChip(icon: Icons.book, label: song.book!),
            ],
            // Tags from global junction table
            ..._buildTagChips(song.id),
          ],
        ),
      ),
    );
  }

  /// Build tag chips from the global junction table.
  List<Widget> _buildTagChips(String songId) {
    final tagIdsAsync = ref.watch(tagsForSongStreamProvider(songId));
    final allTagsAsync = ref.watch(tagsStreamProvider);

    return tagIdsAsync.when(
      data: (tagIds) {
        if (tagIds.isEmpty) return [];
        return allTagsAsync.when(
          data: (allTags) {
            final tagMap = {for (final t in allTags) t.id: t.name};
            return [
              const SizedBox(width: AppTheme.spacing8),
              ...tagIds
                  .where((id) => tagMap.containsKey(id))
                  .map(
                    (id) => Padding(
                      padding: const EdgeInsets.only(right: AppTheme.spacing6),
                      child: _MetadataChip(
                        icon: Icons.label,
                        label: tagMap[id]!,
                      ),
                    ),
                  ),
            ];
          },
          loading: () => [],
          error: (_, _) => [],
        );
      },
      loading: () => [],
      error: (_, _) => [],
    );
  }

  /// Transpose control bar: -/+ buttons and current key display.
  Widget _buildTransposeBar(SongModel song) {
    final displayedKey = _getDisplayedKey(song);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.spacing16,
        0,
        AppTheme.spacing16,
        AppTheme.spacing8,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing12,
        vertical: AppTheme.spacing6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.orange.withValues(alpha: AppTheme.alphaLight),
        borderRadius: AppTheme.borderRadiusLG,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.music_note,
            size: AppTheme.iconMD,
            color: AppTheme.orange,
          ),
          const SizedBox(width: AppTheme.spacing8),
          Text(
            'Transpose',
            style: AppTheme.bodySmallStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.gray700,
            ),
          ),
          const SizedBox(width: AppTheme.spacing12),
          // Minus button
          _TransposeButton(
            icon: Icons.remove,
            onTap: () => _setTransposeSteps(_transposeSteps - 1),
          ),
          // Current offset display
          Container(
            width: 48,
            alignment: Alignment.center,
            child: Text(
              _transposeSteps == 0
                  ? '0'
                  : (_transposeSteps > 0
                        ? '+$_transposeSteps'
                        : '$_transposeSteps'),
              style: AppTheme.headingSmall.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Plus button
          _TransposeButton(
            icon: Icons.add,
            onTap: () => _setTransposeSteps(_transposeSteps + 1),
          ),
          if (displayedKey.isNotEmpty) ...[
            const SizedBox(width: AppTheme.spacing12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing10,
                vertical: AppTheme.spacing4,
              ),
              decoration: BoxDecoration(
                color: AppTheme.orange.withValues(alpha: AppTheme.alphaMedium),
                borderRadius: AppTheme.borderRadiusSM,
              ),
              child: Text(
                displayedKey,
                style: AppTheme.bodyBase.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.orange,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (_transposeSteps != 0)
            TextButton(
              onPressed: () => _setTransposeSteps(0),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing8,
                  vertical: 0,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Reset', style: AppTheme.caption),
            ),
        ],
      ),
    );
  }

  /// Build chord content. Prefers structured chord lines; falls back to legacy inline.
  Widget _buildChordContent(SongModel song) {
    if (song.hasStructuredChords) {
      return _buildStructuredChordView(song);
    }
    // Fall back to legacy inline [chord] notation
    return _buildLegacyChordView(song.chords, song.scale);
  }

  /// Structured chord view: chord lines displayed above their corresponding lyric lines.
  /// Monospaced font for alignment.
  Widget _buildStructuredChordView(SongModel song) {
    final lyricLines = song.lyrics.split('\n');
    final chordLines = song.chordLinesList;
    final useFlats = song.scale.isNotEmpty
        ? ChordTransposer.keyUsesFlats(song.scale)
        : null;

    // Build a map from lineIndex to chord text for O(1) lookups
    final chordMap = <int, String>{};
    for (final cl in chordLines) {
      chordMap[cl.lineIndex] = cl.rawChords;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < lyricLines.length; i++) ...[
          if (chordMap.containsKey(i))
            // Chord line (transposed at render time)
            Text(
              _transposeSteps == 0
                  ? chordMap[i]!
                  : ChordTransposer.transposeLine(
                      chordMap[i]!,
                      _transposeSteps,
                      preferFlats: useFlats,
                    ),
              style: TextStyle(
                fontSize: _isFullscreen ? 15 : 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: AppTheme.orange,
                height: 1.6,
              ),
            ),
          // Lyric line
          Text(
            lyricLines[i],
            style: TextStyle(
              fontSize: _isFullscreen ? 18 : 15,
              fontFamily: 'monospace',
              height: 1.6,
              color: AppTheme.gray800,
            ),
          ),
          if (i < lyricLines.length - 1)
            const SizedBox(height: AppTheme.spacing2),
        ],
      ],
    );
  }

  /// Legacy inline chord view: parses [chord] notation from the chords field.
  Widget _buildLegacyChordView(String chords, String scale) {
    if (chords.isEmpty) {
      return _buildLyricsView('');
    }

    final useFlats = scale.isNotEmpty
        ? ChordTransposer.keyUsesFlats(scale)
        : null;
    final lines = chords.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
          child: _buildLegacyChordLine(line, useFlats),
        );
      }).toList(),
    );
  }

  Widget _buildLegacyChordLine(String line, bool? preferFlats) {
    final matches = _chordRegex.allMatches(line).toList();
    if (matches.isEmpty) {
      return Text(
        line,
        style: TextStyle(
          fontSize: _isFullscreen ? 18 : 15,
          height: 1.6,
          color: AppTheme.gray800,
        ),
      );
    }

    final segments = _parseLegacyLineSegments(line, preferFlats, matches);
    final chordFontSize = _isFullscreen ? 15.0 : 13.0;
    final lyricFontSize = _isFullscreen ? 18.0 : 15.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: segments.map((seg) {
          return IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seg.chord ?? '',
                  style: TextStyle(
                    fontSize: chordFontSize,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: seg.chord != null
                        ? AppTheme.orange
                        : Colors.transparent,
                    height: 1.4,
                  ),
                ),
                Text(
                  seg.lyric,
                  style: TextStyle(
                    fontSize: lyricFontSize,
                    fontFamily: 'monospace',
                    height: 1.6,
                    color: AppTheme.gray800,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Parse a legacy [chord]lyric line into segments of (optional chord, lyric text).
  /// Each chord "owns" the lyric text that immediately follows it, up to the next chord.
  List<_ChordSegment> _parseLegacyLineSegments(
    String line,
    bool? preferFlats,
    List<RegExpMatch> matches,
  ) {
    final segments = <_ChordSegment>[];
    int lastEnd = 0;

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];

      // Plain lyric text before this chord — no chord above it
      if (match.start > lastEnd) {
        segments.add(
          _ChordSegment(
            chord: null,
            lyric: line.substring(lastEnd, match.start),
          ),
        );
      }

      // Lyric text after this chord, up to the next chord (or end of line)
      final nextStart = i + 1 < matches.length
          ? matches[i + 1].start
          : line.length;
      final lyricAfter = line.substring(match.end, nextStart);

      final rawChord = match.group(1)!;
      final displayChord = _transposeSteps == 0
          ? rawChord
          : ChordTransposer.transposeChord(
              rawChord,
              _transposeSteps,
              preferFlats: preferFlats,
            );

      segments.add(_ChordSegment(chord: displayChord, lyric: lyricAfter));
      lastEnd = nextStart;
    }

    return segments;
  }

  Widget _buildNotesSection(String notes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing12),
      decoration: BoxDecoration(
        color: AppTheme.gray100,
        borderRadius: AppTheme.borderRadiusMD,
        border: Border.all(color: AppTheme.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: AppTheme.iconSM,
                color: AppTheme.gray600,
              ),
              const SizedBox(width: AppTheme.spacing6),
              Text(
                'Notes',
                style: AppTheme.bodySmallStyle.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.gray700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing8),
          SelectableText(
            notes,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.gray800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsView(String lyrics) {
    if (lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off, size: 48, color: AppTheme.gray400),
            const SizedBox(height: AppTheme.spacing12),
            Text(
              'No lyrics added yet',
              style: TextStyle(fontSize: 16, color: AppTheme.gray600),
            ),
          ],
        ),
      );
    }

    return SelectableText(
      lyrics,
      style: TextStyle(
        fontSize: _isFullscreen ? 20 : 16,
        height: 1.8,
        color: AppTheme.gray800,
      ),
    );
  }

  /// Compute the displayed key: original scale transposed by the current offset.
  String _getDisplayedKey(SongModel song) {
    if (song.scale.isEmpty) return '';
    if (_transposeSteps == 0) return song.scale;
    return ChordTransposer.transposeKey(
      song.scale,
      _transposeSteps,
      preferFlats: ChordTransposer.keyUsesFlats(song.scale),
    );
  }

  Future<void> _toggleFavorite() async {
    final repository = ref.read(songRepositoryProvider);
    try {
      await repository.toggleFavorite(widget.songId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update favorite: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  void _handleMenuAction(String action, String songId) {
    switch (action) {
      case 'edit':
        context.push('/songs/$songId/edit');
        break;
      case 'share':
        _shareLyrics();
        break;
      case 'duplicate':
        _duplicateSong(songId);
        break;
      case 'delete':
        _confirmDelete(songId);
        break;
    }
  }

  void _shareLyrics() {
    final songAsync = ref.read(songByIdProvider(widget.songId));
    final song = songAsync.valueOrNull;
    if (song == null || song.lyrics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No lyrics to share'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final link = Routes.songDeepLink(widget.songId);
    final text = '${song.title}\n\n${song.lyrics}\n\n$link';
    Share.share(text, subject: song.title);
  }

  Future<void> _confirmDelete(String songId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: const Text(
          'Are you sure you want to move this song to trash?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final repository = ref.read(songRepositoryProvider);
      await repository.trashSong(songId);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Moved to trash'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _duplicateSong(String songId) async {
    final repository = ref.read(songRepositoryProvider);
    try {
      final copy = await repository.duplicateSong(songId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Song duplicated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.push('/songs/${copy.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to duplicate: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }
}

class _ChordSegment {
  final String? chord;
  final String lyric;

  const _ChordSegment({required this.chord, required this.lyric});
}

// ==================== Private Widgets ====================

class _ModeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16,
          vertical: AppTheme.spacing8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: AppTheme.borderRadiusSM,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTheme.bodySmallStyle.fontSize,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppTheme.orange : AppTheme.gray600,
          ),
        ),
      ),
    );
  }
}

class _TransposeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TransposeButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing6),
          child: Icon(icon, size: 18, color: AppTheme.orange),
        ),
      ),
    );
  }
}

class _MetadataChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetadataChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing10,
        vertical: AppTheme.spacing6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.gray100,
        borderRadius: AppTheme.borderRadius3XL,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.iconSM, color: AppTheme.gray600),
          const SizedBox(width: AppTheme.spacing4),
          Text(
            label,
            style: AppTheme.caption.copyWith(color: AppTheme.gray700),
          ),
        ],
      ),
    );
  }
}
