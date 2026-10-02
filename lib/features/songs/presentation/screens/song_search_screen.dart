import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/chord_transposition.dart';
import '../../../../core/sync/models/song_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../widgets/song_filter_dialog.dart';

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

  // One immutable value rather than three mutable fields. The tag set used to
  // be mutated in place from inside a bottom sheet, which is how the screen came
  // to show a selection it had never searched with.
  SongSearchFilters _filters = SongSearchFilters.none;

  /// Held from the tap until the dialog closes. The dialog waits on three
  /// loads before it appears, and a second tap in that gap opened a second
  /// dialog underneath carrying the old filters — so Apply on it quietly undid
  /// whatever had just been applied in the first.
  bool _filtersOpen = false;

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

  /// Bumped by every search; only the newest may write results.
  ///
  /// Two things start a search — typing (after a 250ms pause) and applying
  /// filters — and nothing ordered them. A typed search still in flight when
  /// filters were applied could finish second and put its unfiltered results
  /// on screen under a badge saying filters were on.
  int _searchGeneration = 0;

  Future<void> _performSearch() async {
    final generation = ++_searchGeneration;
    bool isCurrent() => mounted && generation == _searchGeneration;
    setState(() => _isLoading = true);

    final songRepo = ref.read(songRepositoryProvider);
    final userId = ref.read(currentUserIdProvider);

    try {
      // Collect subtree folder IDs for recursive folder filtering
      final filters = _filters;
      List<String>? subtreeFolderIds;
      if (filters.folderId != null) {
        final folderRepo = ref.read(folderRepositoryProvider);
        final descendants =
            await folderRepo.getAllDescendants(filters.folderId!);
        subtreeFolderIds = [
          filters.folderId!,
          ...descendants.map((f) => f.id),
        ];
      }

      final results = await songRepo.searchSongsFiltered(
        userId: userId,
        textQuery: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        scale: filters.scale,
        folderId: filters.folderId,
        folderIds: subtreeFolderIds,
        tagIds: filters.tagIds.isEmpty ? null : filters.tagIds.toList(),
        language: filters.language,
      );

      // A newer search owns the screen now, including its loading state.
      if (!isCurrent()) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _hasSearched = true;
      });
    } catch (_) {
      if (isCurrent()) {
        setState(() {
          _isLoading = false;
          _hasSearched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildSearchField(context),
            ),

            const Divider(height: 1),

            // Results
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  /// The search field, in the songs colours rather than the app's blue.
  ///
  /// The blue was never chosen here. The field set only `border`, and the
  /// theme's `enabledBorder` and `focusedBorder` outrank it, so the app-wide
  /// 2pt brandBlue focus ring drew around it — immediately, since the field
  /// autofocuses — along with a blue cursor and blue selection handles. Every
  /// state is set explicitly now so nothing falls through to the theme.
  Widget _buildSearchField(BuildContext context) {
    // accentInk for anything drawn as a line or glyph: the true orange is too
    // light to clear 3:1 against a light field. The fill and the highlight use
    // the true orange, faintly, because they carry no meaning of their own.
    final ink = context.accentInk(AppTheme.orange);
    final pill = BorderRadius.circular(50);

    return TextSelectionTheme(
      data: TextSelectionThemeData(
        cursorColor: ink,
        selectionColor: AppTheme.orange.withValues(alpha: 0.35),
        selectionHandleColor: ink,
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        cursorColor: ink,
        decoration: InputDecoration(
          hintText: l10n(context).searchByTitle,
          filled: true,
          fillColor: AppTheme.orange.withValues(alpha: AppTheme.alphaLight),
          prefixIcon: Icon(Icons.search, color: ink),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  tooltip: l10n(context).clearSearch,
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    _performSearch();
                  },
                ),
              _buildFilterButton(context),
            ],
          ),
          border: OutlineInputBorder(
            borderRadius: pill,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: pill,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: pill,
            borderSide: BorderSide(color: ink, width: 2),
          ),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  /// Opens the filter dialog. The badge counts the kinds of filter in force —
  /// key, tags, songbook — so it reads 1 to 3, not the number of tags ticked.
  Widget _buildFilterButton(BuildContext context) {
    final count = _filters.activeCount;
    return IconButton(
      tooltip: l10n(context).filterSongs,
      onPressed: _openFilters,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        // The true orange with whichever label clears it — the same pairing
        // as the dialog's Apply button, so the two read as one control.
        backgroundColor: AppTheme.orange,
        textColor: AppTheme.onAccent(AppTheme.orange),
        child: Icon(
          Icons.filter_list_rounded,
          color: count > 0
              ? context.accentInk(AppTheme.orange)
              : context.mutedText,
        ),
      ),
    );
  }

  Future<void> _openFilters() async {
    if (_filtersOpen) return;
    _filtersOpen = true;
    try {
      await _runFilterDialog();
    } finally {
      _filtersOpen = false;
    }
  }

  Future<void> _runFilterDialog() async {
    // Awaited rather than read with valueOrNull: a dialog opened before the
    // tags had loaded would otherwise say "No tags available" when there are
    // tags — a wrong answer, not a missing one. These are local queries, so the
    // wait is a frame or two. A failure still opens the dialog, without that
    // section's choices, which is what the old chips did.
    Future<List<T>> load<T>(Future<List<T>> f, String what) =>
        f.catchError((Object e) {
          debugPrint('SongSearchScreen: failed to load $what: $e');
          return <T>[];
        });

    // The keys, tags and languages come from FutureProviders, which load once
    // and are then kept for the session. Read as they were, the dialog offered
    // the choices of whenever it was first opened: a song added in Tamil, or a
    // new tag, did not appear until the app restarted. Refreshed on each open
    // instead — three small local queries, the last on an indexed column.
    // Songbooks need nothing: theirs is a stream, and already current.
    ref
      ..invalidate(songScalesProvider)
      ..invalidate(songTagsProvider)
      ..invalidate(songLanguagesProvider);

    final (dbScales, tags, songbooks, languages) = await (
      load(ref.read(songScalesProvider.future), 'scales'),
      load(ref.read(songTagsProvider.future), 'tags'),
      load(ref.read(songFoldersStreamProvider.future), 'songbooks'),
      load(ref.read(songLanguagesProvider.future), 'languages'),
    ).wait;
    if (!mounted) return;

    // Majors, then minors, each in the chromatic order ChordTransposer already
    // lists them in. Sorting the merged set alphabetically — which this did —
    // interleaved them as A, Ab, Abm, Am, B…, so finding G meant reading the
    // whole grid. Any key a song carries that the standard lists lack goes at
    // the end rather than being dropped.
    const standard = [
      ...ChordTransposer.majorKeys,
      ...ChordTransposer.minorKeys,
    ];
    final extra = dbScales.where((k) => !standard.contains(k)).toSet().toList()
      ..sort();
    final scales = [...standard, ...extra];

    final chosen = await SongFilterDialog.show(
      context,
      initial: _filters,
      scales: scales,
      tags: tags,
      songbooks: songbooks,
      languages: languages,
    );
    if (chosen == null || chosen == _filters || !mounted) return;

    setState(() => _filters = chosen);
    _performSearch();
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
              child: Icon(Icons.music_note,
                  color: context.accentInk(AppTheme.orange), size: 18),
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
                            style: TextStyle(
                              fontSize: 12,
                              color: context.accentInk(AppTheme.orange),
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
