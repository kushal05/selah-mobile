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
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Song Search'),
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
                  hintText: 'Search by title...',
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
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
                      data: (scales) => _FilterChip(
                        label: _selectedScale == null
                            ? 'Key'
                            : 'Key: $_selectedScale',
                        isActive: _selectedScale != null,
                        onTap: () => _showScaleFilter(scales),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) {
                        debugPrint('SongSearchScreen: failed to load scales: $e');
                        return const SizedBox.shrink();
                      },
                    ),
                    const SizedBox(width: 8),

                    // Tag filters
                    tagsAsync.when(
                      data: (tags) => _FilterChip(
                        label: _selectedTags.isEmpty
                            ? 'Tags'
                            : 'Tags (${_selectedTags.length})',
                        isActive: _selectedTags.isNotEmpty,
                        onTap: () => _showTagFilter(tags),
                      ),
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
                        return _FilterChip(
                          label: activeFolderName ?? 'Songbook',
                          isActive: _selectedFolderId != null,
                          onTap: () => _showFolderFilter(folders),
                        );
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
                        label: const Text('Clear all',
                            style: TextStyle(fontSize: 12)),
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
            Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No songs found',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
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
              child: Text('Filter by Key',
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
                            : Colors.grey,
                      ),
                      title: const Text('Any key'),
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
                                : Colors.grey,
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
                    Text('Filter by Tags',
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
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (availableTags.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No tags available'),
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
              child: Text('Filter by Songbook',
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
                    : Colors.grey,
              ),
              title: const Text('All songbooks'),
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
                        : Colors.grey,
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
          color: Colors.white,
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
                        fontSize: 15, fontWeight: FontWeight.w600),
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
                              fontSize: 10,
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
                            fontSize: 12, color: Colors.grey.shade600),
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

// ==================== Filter Chip Widget ====================

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primary.withValues(alpha: 0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive
                  ? colorScheme.primary.withValues(alpha: 0.4)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isActive ? colorScheme.primary : Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: isActive ? colorScheme.primary : Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600),
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
