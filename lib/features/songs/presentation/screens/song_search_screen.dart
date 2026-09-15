import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/chord_transposition.dart';
import '../../../../core/sync/models/song_model.dart';
import '../../../../core/sync/models/tag_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/filter_pill.dart';

/// Dedicated Song Search screen with combinable filters.
/// Filters: tags (multi-select), scale/key (single), folder, free-text (title).
/// Runs entirely offline using Realm/Drift queries.
class SongSearchScreen extends ConsumerStatefulWidget {
  const SongSearchScreen({super.key});

  @override
  ConsumerState<SongSearchScreen> createState() => _SongSearchScreenState();
}

class _SongSearchScreenState extends ConsumerState<SongSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<SongModel> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  // Filter state
  String? _selectedScale;
  String? _selectedFolderId;
  final Set<String> _selectedTags = {};

  @override
  void initState() {
    super.initState();
    // Run initial unfiltered search on open
    WidgetsBinding.instance.addPostFrameCallback((_) => _performSearch());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    // Trigger rebuild so the clear button appears/disappears
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    setState(() => _isLoading = true);

    final songRepo = ref.read(songRepositoryProvider);
    final userId = ref.read(currentUserIdProvider);

    try {
      // Collect subtree folder IDs for recursive folder filtering
      List<String>? subtreeFolderIds;
      if (_selectedFolderId != null) {
        final folderRepo = ref.read(folderRepositoryProvider);
        final descendants =
            await folderRepo.getAllDescendants(_selectedFolderId!);
        subtreeFolderIds = [
          _selectedFolderId!,
          ...descendants.map((f) => f.id),
        ];
      }

      final results = await songRepo.searchSongsFiltered(
        userId: userId,
        textQuery: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        scale: _selectedScale,
        folderId: _selectedFolderId,
        folderIds: subtreeFolderIds,
        tagIds: _selectedTags.isEmpty ? null : _selectedTags.toList(),
      );

      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _hasSearched = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(songTagsProvider);
    final scalesAsync = ref.watch(songScalesProvider);
    final foldersAsync = ref.watch(songFoldersStreamProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          tooltip: l10n(context).actionBack,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n(context).songSearch),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n(context).searchByTitle,
                  filled: true,
                  fillColor: context.subtleFill,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                        tooltip: l10n(context).clearSearch,
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _performSearch();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(50),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),

            // Filter chips row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Scale filter
                    scalesAsync.when(
                      data: (scales) => FilterPill(
                        label: _selectedScale == null
                            ? 'Key'
                            : 'Key: $_selectedScale',
                        selected: _selectedScale != null,
                        onTap: () => _showScaleFilter(scales),
                        accent: AppTheme.orange,),
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) {
                        debugPrint('SongSearchScreen: failed to load scales: $e');
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(width: 8),

                    // Tag filters
                    tagsAsync.when(
                      data: (tags) => FilterPill(
                        label: _selectedTags.isEmpty
                            ? 'Tags'
                            : 'Tags (${_selectedTags.length})',
                        selected: _selectedTags.isNotEmpty,
                        onTap: () => _showTagFilter(tags),
                        accent: AppTheme.orange,),
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) {
                        debugPrint('SongSearchScreen: failed to load tags: $e');
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(width: 8),

                    // Folder filter
                    foldersAsync.when(
                      data: (folders) {
                        if (folders.isEmpty) return const SizedBox.shrink();
                        final activeFolderName = _selectedFolderId != null
                            ? folders
                                .where((f) => f.id == _selectedFolderId)
                                .map((f) => f.name)
                                .firstOrNull
                            : null;
                        return FilterPill(
                          label: activeFolderName ?? 'Songbook',
                          selected: _selectedFolderId != null,
                          onTap: () => _showFolderFilter(folders),
                          accent: AppTheme.orange,);
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) {
                        debugPrint('SongSearchScreen: failed to load folders: $e');
                        return const SizedBox.shrink();
                      },
                    ),

                    // Clear all filters
                    if (_selectedScale != null ||
                        _selectedTags.isNotEmpty ||
                        _selectedFolderId != null) ...[
                      const SizedBox(width: 8),
                      ActionChip(
                        label: Text(l10n(context).clearAll,
                            style: TextStyle(fontSize: 13)),
                        onPressed: () {
                          setState(() {
                            _selectedScale = null;
                            _selectedFolderId = null;
                            _selectedTags.clear();
                          });
                          _performSearch();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1),

            // Results
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const ListTileSkeletonList(count: 6, hasLeading: false);
    }

    if (!_hasSearched) {
      return const SizedBox.shrink();
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: context.mutedText),
            const SizedBox(height: 12),
            Text(
              l10n(context).noSongsFound,
              style: TextStyle(fontSize: 16, color: context.mutedText),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final song = _results[index];
        return _SongSearchResultCard(
          song: song,
          searchQuery: _searchController.text.trim(),
          onTap: () => context.push('/songs/${song.id}'),
        );
      },
    );
  }

  // ==================== Filter Dialogs ====================

  void _showScaleFilter(List<String> scales) {
    final allScales = [
      ...ChordTransposer.majorKeys,
      ...ChordTransposer.minorKeys,
    ];
    // Merge DB scales with standard scale list, avoiding duplicates
    final mergedScales = <String>{...allScales, ...scales}.toList()..sort();

    showModalBottomSheet(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n(context).filterByKey,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: Icon(
                        _selectedScale == null
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: _selectedScale == null
                            ? Theme.of(context).primaryColor
                            : context.mutedText,
                      ),
                      title: Text(l10n(context).anyKey),
                      onTap: () {
                        setState(() => _selectedScale = null);
                        Navigator.pop(ctx);
                        _performSearch();
                      },
                    ),
                    ...mergedScales.map((s) => ListTile(
                          leading: Icon(
                            _selectedScale == s
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: _selectedScale == s
                                ? Theme.of(context).primaryColor
                                : context.mutedText,
                          ),
                          title: Text(s),
                          dense: true,
                          onTap: () {
                            setState(() => _selectedScale = s);
                            Navigator.pop(ctx);
                            _performSearch();
                          },
                        )),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTagFilter(List<TagModel> availableTags) {
    showModalBottomSheet(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(l10n(context).filterByTags,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _performSearch();
                      },
                      child: Text(l10n(context).apply),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (availableTags.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(l10n(context).noTagsAvailable),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: availableTags.map((tag) {
                        final selected = _selectedTags.contains(tag.id);
                        return CheckboxListTile(
                          title: Text(tag.name),
                          value: selected,
                          onChanged: (v) {
                            setSheetState(() {
                              setState(() {
                                if (v == true) {
                                  _selectedTags.add(tag.id);
                                } else {
                                  _selectedTags.remove(tag.id);
                                }
                              });
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showFolderFilter(List<dynamic> folders) {
    showModalBottomSheet(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n(context).filterBySongbook,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                _selectedFolderId == null
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: _selectedFolderId == null
                    ? Theme.of(context).primaryColor
                    : context.mutedText,
              ),
              title: Text(l10n(context).allSongbooks),
              onTap: () {
                setState(() => _selectedFolderId = null);
                Navigator.pop(ctx);
                _performSearch();
              },
            ),
            ...folders.map((folder) => ListTile(
                  leading: Icon(
                    _selectedFolderId == folder.id
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: _selectedFolderId == folder.id
                        ? Theme.of(context).primaryColor
                        : context.mutedText,
                  ),
                  title: Text(folder.name),
                  onTap: () {
                    setState(() => _selectedFolderId = folder.id);
                    Navigator.pop(ctx);
                    _performSearch();
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ==================== Result Card ====================

class _SongSearchResultCard extends StatelessWidget {
  final SongModel song;
  final String searchQuery;
  final VoidCallback onTap;

  const _SongSearchResultCard({
    required this.song,
    required this.searchQuery,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Find matching lyric snippet if text search is active
    String? lyricSnippet;
    if (searchQuery.isNotEmpty && song.lyrics.isNotEmpty) {
      final lowerLyrics = song.lyrics.toLowerCase();
      final lowerQuery = searchQuery.toLowerCase();
      final idx = lowerLyrics.indexOf(lowerQuery);
      if (idx >= 0) {
        // Extract a window around the match
        final start = (idx - 20).clamp(0, song.lyrics.length);
        final end = (idx + searchQuery.length + 40).clamp(0, song.lyrics.length);
        final raw = song.lyrics.substring(start, end).replaceAll('\n', ' ');
        lyricSnippet = '${start > 0 ? '...' : ''}$raw${end < song.lyrics.length ? '...' : ''}';
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.cardSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Music icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.music_note,
                  color: AppTheme.orange, size: 18),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    song.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Scale + language row
                  Row(
                    children: [
                      if (song.scale.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.orange
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Key: ${song.scale}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.orange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        song.language,
                        style: TextStyle(
                            fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),

                  // Tag chips from junction table
                  _SongTagChips(songId: song.id),

                  // Lyric snippet (if text search matched lyrics)
                  if (lyricSnippet != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      lyricSnippet,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.mutedText,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            Icon(Icons.chevron_right, color: context.hintText),
          ],
        ),
      ),
    );
  }
}

// ==================== Filter Chip Widget ====================


/// Displays tag chips for a song, resolved from the junction table.
class _SongTagChips extends ConsumerWidget {
  final String songId;

  const _SongTagChips({required this.songId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagIdsAsync = ref.watch(tagsForSongStreamProvider(songId));
    final allTagsAsync = ref.watch(tagsStreamProvider);

    return tagIdsAsync.when(
      data: (tagIds) {
        if (tagIds.isEmpty) return const SizedBox.shrink();
        return allTagsAsync.when(
          data: (allTags) {
            final tagMap = {for (final t in allTags) t.id: t.name};
            final names = tagIds
                .where((id) => tagMap.containsKey(id))
                .map((id) => tagMap[id]!)
                .take(3)
                .toList();
            if (names.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: names
                    .map((tag) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.subtleFill,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                                fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ))
                    .toList(),
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (e, _) {
            debugPrint('_SongTagChips: failed to load all tags: $e');
            return const SizedBox.shrink();
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) {
        debugPrint('_SongTagChips: failed to load tag IDs: $e');
        return const SizedBox.shrink();
      },
    );
  }
}
