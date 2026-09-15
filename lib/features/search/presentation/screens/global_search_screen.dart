import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/sync/models/song_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lists/search_section.dart';
import '../../../songs/presentation/screens/song_detail_screen.dart';
import '../../../notes/presentation/screens/note_detail_screen.dart';
import '../../../prayers/presentation/screens/prayer_detail_screen.dart';
import '../../../promises/presentation/screens/promise_detail_screen.dart';
import '../../../people/presentation/screens/person_detail_screen.dart';
import '../../../../shared/widgets/cards/search_row.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../providers/global_search_provider.dart';
import '../utils/search_result_formatter.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/filter_pill.dart';

/// Entity types available for filtering search results.
enum SearchEntityType { songs, notes, prayers, promises, people }

/// Global search screen for searching across all content.
/// Song results now include lyrics content matching, highlighted snippet, and scale.
/// Results grouped by type: Songs, Notes, Prayers, Promises, People.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() =>
      _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  /// Active entity type filters. Empty set means "show all".
  final Set<SearchEntityType> _activeFilters = {};

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      ref.read(globalSearchProvider.notifier).clear();
      // Trigger rebuild so the clear button appears/disappears
      setState(() {});
      return;
    }
    // Trigger rebuild so the clear button appears/disappears
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(globalSearchProvider.notifier).search(query.trim());
    });
  }

  bool _isFilterActive(SearchEntityType type) =>
      _activeFilters.isEmpty || _activeFilters.contains(type);

  bool _hasFilteredResults(GlobalSearchState searchState) =>
      (searchState.songs.isNotEmpty && _isFilterActive(SearchEntityType.songs)) ||
      (searchState.notes.isNotEmpty && _isFilterActive(SearchEntityType.notes)) ||
      (searchState.prayers.isNotEmpty && _isFilterActive(SearchEntityType.prayers)) ||
      (searchState.promises.isNotEmpty && _isFilterActive(SearchEntityType.promises)) ||
      (searchState.people.isNotEmpty && _isFilterActive(SearchEntityType.people));

  void _toggleFilter(SearchEntityType type) {
    setState(() {
      if (_activeFilters.contains(type)) {
        _activeFilters.remove(type);
      } else {
        _activeFilters.add(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(globalSearchProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          tooltip: l10n(context).actionBack,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n(context).searchAcrossAllContent,
                  filled: true,
                  fillColor: context.subtleFill,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                        tooltip: l10n(context).clearSearch,
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
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
              const SizedBox(height: 12),
              _buildFilterChips(),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(searchState)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          FilterPill(
            label: l10n(context).all,
            icon: Icons.select_all_rounded,
            selected: _activeFilters.isEmpty,
            onTap: () => setState(() => _activeFilters.clear()),
            accent: AppTheme.brandBlue,),
          const SizedBox(width: 8),
          FilterPill(
            label: l10n(context).navSongs,
            icon: Icons.music_note_rounded,
            selected: _activeFilters.contains(SearchEntityType.songs),
            onTap: () => _toggleFilter(SearchEntityType.songs),
            accent: AppTheme.brandBlue,),
          const SizedBox(width: 8),
          FilterPill(
            label: l10n(context).navNotes,
            icon: Icons.note_rounded,
            selected: _activeFilters.contains(SearchEntityType.notes),
            onTap: () => _toggleFilter(SearchEntityType.notes),
            accent: AppTheme.brandBlue,),
          const SizedBox(width: 8),
          FilterPill(
            label: l10n(context).navPrayers,
            icon: Icons.volunteer_activism_rounded,
            selected: _activeFilters.contains(SearchEntityType.prayers),
            onTap: () => _toggleFilter(SearchEntityType.prayers),
            accent: AppTheme.brandBlue,),
          const SizedBox(width: 8),
          FilterPill(
            label: l10n(context).navPromises,
            icon: Icons.auto_stories_rounded,
            selected: _activeFilters.contains(SearchEntityType.promises),
            onTap: () => _toggleFilter(SearchEntityType.promises),
            accent: AppTheme.brandBlue,),
          const SizedBox(width: 8),
          FilterPill(
            label: l10n(context).people,
            icon: Icons.people_rounded,
            selected: _activeFilters.contains(SearchEntityType.people),
            onTap: () => _toggleFilter(SearchEntityType.people),
            accent: AppTheme.brandBlue,),
        ],
      ),
    );
  }

  Widget _buildBody(GlobalSearchState searchState) {
    if (searchState.isLoading) {
      return const Column(
        children: [
          ListTileSkeleton(hasLeading: false),
          ListTileSkeleton(hasLeading: false),
          ListTileSkeleton(),
          ListTileSkeleton(hasLeading: false),
          ListTileSkeleton(),
          ListTileSkeleton(hasLeading: false),
        ],
      );
    }

    if (!searchState.hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: context.mutedText),
            const SizedBox(height: 16),
            Text(
              l10n(context).startTypingToSearch,
              style: TextStyle(fontSize: 16, color: context.mutedText),
            ),
          ],
        ),
      );
    }

    if (!searchState.hasResults) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: context.mutedText),
            const SizedBox(height: 16),
            Text(
              l10n(context).noResultsFound,
              style: TextStyle(fontSize: 16, color: context.mutedText),
            ),
          ],
        ),
      );
    }

    // Check if results exist but are all hidden by active filters
    if (_activeFilters.isNotEmpty && !_hasFilteredResults(searchState)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.filter_list_off, size: 64, color: context.mutedText),
            const SizedBox(height: 16),
            Text(
              l10n(context).noResultsForSelectedFilters,
              style: TextStyle(fontSize: 16, color: context.mutedText),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _activeFilters.clear()),
              style: TextButton.styleFrom(foregroundColor: context.mutedText),
              child: Text(l10n(context).clearFilters),
            ),
          ],
        ),
      );
    }

    final query = _searchController.text.trim();

    // Results grouped by type per spec: Songs, Notes, Prayers, Promises, People
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SONGS — enhanced: shows title, scale, highlighted lyric snippet
          if (searchState.songs.isNotEmpty && _isFilterActive(SearchEntityType.songs))
            SearchSection(
              title: l10n(context).songs,
              children: searchState.songs
                  .map((s) => _SongSearchRow(
                        song: s,
                        lyricSnippet: getLyricSnippet(s, query),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SongDetailScreen(songId: s.id),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          if (searchState.notes.isNotEmpty && _isFilterActive(SearchEntityType.notes))
            SearchSection(
              title: l10n(context).notes,
              children: searchState.notes
                  .map((n) => SearchRow(
                        title: n.displayTitle,
                        subtitle: getNoteSubtitle(n, query),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NoteDetailScreen(noteId: n.id),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          if (searchState.prayers.isNotEmpty && _isFilterActive(SearchEntityType.prayers))
            SearchSection(
              title: l10n(context).prayers,
              children: searchState.prayers
                  .map((p) => SearchRow(
                        title: p.title,
                        subtitle:
                            '${p.status.name[0].toUpperCase()}${p.status.name.substring(1)} • ${p.frequency.name}',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PrayerDetailScreen(prayerId: p.id),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          if (searchState.promises.isNotEmpty && _isFilterActive(SearchEntityType.promises))
            SearchSection(
              title: l10n(context).promises,
              children: searchState.promises
                  .map((p) => SearchRow(
                        title: p.reference,
                        subtitle: p.content.length > 60
                            ? '${p.content.substring(0, 60)}...'
                            : p.content,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PromiseDetailScreen(promiseId: p.id),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          if (searchState.people.isNotEmpty && _isFilterActive(SearchEntityType.people))
            SearchSection(
              title: l10n(context).people2,
              children: searchState.people
                  .map((p) => SearchRow(
                        title: p.name,
                        subtitle: p.relation,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PersonDetailScreen(personId: p.id),
                          ),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

/// Enhanced song search result row for Global Search.
/// Shows title, scale (key), highlighted lyric snippet.
class _SongSearchRow extends StatelessWidget {
  final SongModel song;
  final String lyricSnippet;
  final VoidCallback? onTap;

  const _SongSearchRow({
    required this.song,
    required this.lyricSnippet,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Build subtitle: scale + language + book
    final parts = <String>[];
    if (song.scale.isNotEmpty) parts.add('Key: ${song.scale}');
    parts.add(song.language);
    if (song.book != null && song.book!.isNotEmpty) parts.add(song.book!);
    final subtitle = parts.join(' • ');

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  if (lyricSnippet.isNotEmpty) ...[
                    const SizedBox(height: 4),
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

