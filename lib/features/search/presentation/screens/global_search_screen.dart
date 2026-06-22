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
                  hintText: 'Search across all content',
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
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
          _FilterChip(
            label: 'All',
            icon: Icons.select_all_rounded,
            isSelected: _activeFilters.isEmpty,
            onTap: () => setState(() => _activeFilters.clear()),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Songs',
            icon: Icons.music_note_rounded,
            isSelected: _activeFilters.contains(SearchEntityType.songs),
            onTap: () => _toggleFilter(SearchEntityType.songs),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Notes',
            icon: Icons.note_rounded,
            isSelected: _activeFilters.contains(SearchEntityType.notes),
            onTap: () => _toggleFilter(SearchEntityType.notes),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Prayers',
            icon: Icons.volunteer_activism_rounded,
            isSelected: _activeFilters.contains(SearchEntityType.prayers),
            onTap: () => _toggleFilter(SearchEntityType.prayers),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Promises',
            icon: Icons.auto_stories_rounded,
            isSelected: _activeFilters.contains(SearchEntityType.promises),
            onTap: () => _toggleFilter(SearchEntityType.promises),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'People',
            icon: Icons.people_rounded,
            isSelected: _activeFilters.contains(SearchEntityType.people),
            onTap: () => _toggleFilter(SearchEntityType.people),
          ),
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
            Icon(Icons.search, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Start typing to search...',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
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
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
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
            Icon(Icons.filter_list_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'No results for selected filters',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _activeFilters.clear()),
              style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
              child: const Text('Clear filters'),
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
              title: 'SONGS',
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
              title: 'NOTES',
              children: searchState.notes
                  .map((n) => SearchRow(
                        title: n.title,
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
              title: 'PRAYERS',
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
              title: 'PROMISES',
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
              title: 'PEOPLE',
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
          color: Colors.white,
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
                        fontSize: 14, color: Colors.grey.shade600),
                  ),
                  if (lyricSnippet.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      lyricSnippet,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

/// Styled filter chip for entity type filtering.
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.brandPurple
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
