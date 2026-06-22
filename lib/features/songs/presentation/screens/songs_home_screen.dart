import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/models/folder_model.dart';
import '../../../../core/sync/utils/sync_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/song_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/cards/song_card.dart';
import '../../../../shared/widgets/dialogs/create_folder_dialog.dart';
import '../../../../shared/widgets/dialogs/edit_folder_dialog.dart';
import '../../../../shared/widgets/dialogs/folder_selection_dialog.dart';
import '../../../../shared/widgets/lists/folder_row.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Songs home screen with list view and multi-select support
/// Displays songs organized by folders with search and filter options
class SongsHomeScreen extends ConsumerStatefulWidget {
  const SongsHomeScreen({super.key});

  @override
  ConsumerState<SongsHomeScreen> createState() => _SongsHomeScreenState();
}

class _SongsHomeScreenState extends ConsumerState<SongsHomeScreen> {
  bool _isSelecting = false;
  bool _showingTrash = false;
  final Set<String> _selectedSongIds = {};

  // Folder browsing state
  String? _selectedFolderId;
  final Set<String> _expandedFolders = {};
  bool _isFolderSectionExpanded = false;

  void _enterSelectMode({String? initialSongId}) {
    setState(() {
      _isSelecting = true;
      _selectedSongIds.clear();
      if (initialSongId != null) {
        _selectedSongIds.add(initialSongId);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _isSelecting = false;
      _selectedSongIds.clear();
    });
  }

  void _toggleSongSelection(String songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
        if (_selectedSongIds.isEmpty) {
          _isSelecting = false;
        }
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = StatefulNavigationShell.of(context);
    final songsAsync = _showingTrash
        ? ref.watch(trashedSongsStreamProvider)
        : ref.watch(songsStreamProvider);
    final foldersAsync = ref.watch(songFoldersStreamProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          if (_showingTrash) {
            setState(() => _showingTrash = false);
          } else if (_isSelecting) {
            _exitSelectMode();
          } else {
            shell.goBranch(0);
          }
        }
      },
      child: Scaffold(
        appBar: _isSelecting
            ? _buildSelectionAppBar()
            : _showingTrash
                ? _buildTrashAppBar(context)
                : _buildNormalAppBar(context),
        floatingActionButton: _isSelecting || _showingTrash
            ? null
            : FloatingActionButton(
                heroTag: null,
                onPressed: () => context.push('/songs/new'),
                backgroundColor: AppTheme.orange,
                foregroundColor: Colors.white,
                child: const Icon(Icons.add),
              ),
        body: _showingTrash
            ? _buildTrashBody(songsAsync)
            : songsAsync.when(
          loading: () => const ListTileSkeletonList(count: 8, hasLeading: false),
          error: (error, stack) => Center(child: Text('Error: $error')),
          data: (songs) {
            // Filter songs by selected folder
            final filteredSongs = _selectedFolderId == null
                ? songs
                : songs
                    .where((s) => s.folderId == _selectedFolderId)
                    .toList();

            // Resolve selected folder name
            final folders = foldersAsync.valueOrNull ?? [];
            final selectedFolderName = _selectedFolderId == null
                ? 'All Songs'
                : folders
                        .where((f) => f.id == _selectedFolderId)
                        .map((f) => f.name)
                        .firstOrNull ??
                    'All Songs';

            return CustomScrollView(
              slivers: [

                  // Collapsible folder section (hidden during selection)
                  if (!_isSelecting)
                    SliverToBoxAdapter(
                      child: _buildFolderSection(songs, folders),
                    ),

                  // Favorites section (hidden during selection and folder filter)
                  if (!_isSelecting &&
                      _selectedFolderId == null &&
                      songs.any((s) => s.isFavorite)) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          'Favorites',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    Builder(builder: (context) {
                      final favoriteSongs =
                          songs.where((s) => s.isFavorite).toList();
                      return SliverToBoxAdapter(
                        child: SizedBox(
                          height: 120,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: favoriteSongs.length,
                            itemBuilder: (context, index) {
                              final song = favoriteSongs[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: _FavoriteCard(
                                  title: song.title,
                                  language: song.language,
                                  hasChords: song.hasChords,
                                  onTap: () =>
                                      context.push('/songs/${song.id}'),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],

                  // Songs section header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        selectedFolderName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),

                  // Songs list
                  if (filteredSongs.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildEmptyState(context),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = filteredSongs[index];
                          final isSelected =
                              _selectedSongIds.contains(song.id);

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: _isSelecting
                                ? _buildSelectableSongRow(
                                    song, isSelected)
                                : Slidable(
                                    key: Key(song.id),
                                    endActionPane: ActionPane(
                                      motion: const DrawerMotion(),
                                      extentRatio: 0.4,
                                      children: [
                                        SlidableAction(
                                          onPressed: (ctx) =>
                                              _moveSong(ctx, song.id),
                                          backgroundColor:
                                              AppTheme.orange,
                                          foregroundColor: Colors.white,
                                          icon: Icons
                                              .drive_file_move_outlined,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        SlidableAction(
                                          onPressed: (ctx) async {
                                            final shouldDelete =
                                                await _showDeleteConfirmation(
                                                    ctx);
                                            if (shouldDelete &&
                                                ctx.mounted) {
                                              await _deleteSong(
                                                  ctx, song.id);
                                            }
                                          },
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                          icon: Icons.delete,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ],
                                    ),
                                    child: GestureDetector(
                                      onLongPress: () =>
                                          _enterSelectMode(
                                              initialSongId: song.id),
                                      child: SongCard(
                                        title: song.title,
                                        language: song.language,
                                        scale: song.scale,
                                        hasChords: song.hasChords,
                                        isFavorite: song.isFavorite,
                                        preview: song.preview,
                                        onTap: () => context
                                            .push('/songs/${song.id}'),
                                        onFavoriteToggle: () =>
                                            _toggleFavorite(song.id),
                                      ),
                                    ),
                                  ),
                          );
                        },
                        childCount: filteredSongs.length,
                      ),
                    ),

                // Bottom padding
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            );
          },
        ),
      ),
    );
  }


  AppBar _buildNormalAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Text(
        'Songs',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.search, color: Colors.grey.shade600),
          onPressed: () => context.push('/songs/search'),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
          tooltip: 'Show trash',
          onPressed: () {
            setState(() => _showingTrash = true);
          },
        ),
      ],
    );
  }

  AppBar _buildTrashAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          setState(() => _showingTrash = false);
        },
      ),
      title: Text(
        'Trash',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }

  Widget _buildTrashBody(AsyncValue<List<SongModel>> songsAsync) {
    return songsAsync.when(
      loading: () => const ListTileSkeletonList(count: 8, hasLeading: false),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (songs) {
        if (songs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'Trash is empty',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: songs.length,
          separatorBuilder: (_, i) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final song = songs[index];
            return ListTile(
              title: Text(
                song.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                song.language,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () async {
                      try {
                        await ref.read(songRepositoryProvider).restoreSong(song.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Song restored'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to restore: $e'),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever),
                    tooltip: 'Delete permanently',
                    color: Colors.red,
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Permanently'),
                              content: const Text(
                                  'This song will be permanently deleted. This cannot be undone.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  style: TextButton.styleFrom(
                                      foregroundColor: Colors.red),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                      if (confirmed && context.mounted) {
                        try {
                          await ref
                              .read(songRepositoryProvider)
                              .deleteSong(song.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Song permanently deleted'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to delete: $e'),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  AppBar _buildSelectionAppBar() {
    final count = _selectedSongIds.length;
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectMode,
      ),
      title: Text(
        '$count selected',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.drive_file_move_outlined),
          tooltip: 'Move',
          onPressed: count > 0 ? _moveSelectedSongs : null,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Move to Trash',
          onPressed: count > 0 ? _deleteSelectedSongs : null,
        ),
      ],
    );
  }

  Widget _buildSelectableSongRow(SongModel song, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleSongSelection(song.id),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            activeColor: AppTheme.orange,
            onChanged: (_) => _toggleSongSelection(song.id),
          ),
          Expanded(
            child: SongCard(
              title: song.title,
              language: song.language,
              scale: song.scale,
              hasChords: song.hasChords,
              isFavorite: song.isFavorite,
              preview: song.preview,
              onTap: () => _toggleSongSelection(song.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderSection(List<SongModel> songs, List<FolderModel> folders) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsible header
          InkWell(
            onTap: () {
              setState(() {
                _isFolderSectionExpanded = !_isFolderSectionExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.library_books_rounded,
                    size: 20,
                    color: AppTheme.orange.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Songbooks',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  if (_isFolderSectionExpanded)
                    GestureDetector(
                      onTap: () => _createSongbook(),
                      child: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: AppTheme.orange,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    _isFolderSectionExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),

          // Folder tree (visible when expanded)
          if (_isFolderSectionExpanded) ...[
            // "All Songs" option
            FolderRow(
              title: 'All Songs',
              noteCount: songs.length,
              accentColor: AppTheme.orange,
              depth: 0,
              hasChildren: false,
              isExpanded: false,
              isActive: _selectedFolderId == null,
              onTap: () {
                setState(() {
                  _selectedFolderId = null;
                });
              },
            ),

            // Root folders + recursive children
            ..._buildFolderTree(folders, songs),

            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildFolderTree(
      List<FolderModel> allFolders, List<SongModel> songs) {
    final rootFolders =
        allFolders.where((f) => f.parentId == null).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final widgets = <Widget>[];
    for (final folder in rootFolders) {
      widgets
          .addAll(_buildFolderTreeItems(folder, allFolders, songs, depth: 0));
    }
    return widgets;
  }

  List<Widget> _buildFolderTreeItems(
    FolderModel folder,
    List<FolderModel> allFolders,
    List<SongModel> songs, {
    required int depth,
  }) {
    final children =
        allFolders.where((f) => f.parentId == folder.id).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedFolders.contains(folder.id);
    final isActive = _selectedFolderId == folder.id;
    final songCount = songs.where((s) => s.folderId == folder.id).length;

    final widgets = <Widget>[
      FolderRow(
        title: folder.name,
        noteCount: songCount,
        accentColor: AppTheme.orange,
        depth: depth,
        hasChildren: hasChildren,
        isExpanded: isExpanded,
        isActive: isActive,
        visibility: folder.visibility,
        onTap: () {
          setState(() {
            _selectedFolderId = folder.id;
          });
        },
        onLongPress: () => _editSongbook(folder),
        onExpandToggle: hasChildren
            ? () {
                setState(() {
                  if (isExpanded) {
                    _expandedFolders.remove(folder.id);
                  } else {
                    _expandedFolders.add(folder.id);
                  }
                });
              }
            : null,
      ),
    ];

    if (isExpanded && hasChildren) {
      for (final child in children) {
        widgets.addAll(
            _buildFolderTreeItems(child, allFolders, songs, depth: depth + 1));
      }
    }

    return widgets;
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.music_note, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'No songs yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first song',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createSongbook() async {
    await CreateFolderDialog.show(context, folderType: 'song');
  }

  Future<void> _editSongbook(FolderModel folder) async {
    await EditFolderDialog.show(context, folder);
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Move to Trash'),
            content: const Text('Are you sure you want to move this song to trash?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Move to Trash'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteSong(BuildContext context, String songId) async {
    final repository = ref.read(songRepositoryProvider);
    try {
      await repository.trashSong(songId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Moved to trash'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to move song to trash: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleFavorite(String songId) async {
    final repository = ref.read(songRepositoryProvider);
    try {
      await repository.toggleFavorite(songId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update favorite: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _moveSong(BuildContext context, String songId) async {
    final result = await FolderSelectionDialog.show(
      context,
      folderType: 'song',
    );
    if (result == null || !mounted) return;

    final repository = ref.read(songRepositoryProvider);
    try {
      await repository.moveSong(songId, result.folderId);
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(
            content: Text('Song moved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: Text('Failed to move song: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _moveSelectedSongs() async {
    final result = await FolderSelectionDialog.show(
      context,
      folderType: 'song',
    );
    if (result == null || !mounted) return;

    final repository = ref.read(songRepositoryProvider);
    final ids = _selectedSongIds.toList();
    var movedCount = 0;

    for (final id in ids) {
      try {
        await repository.moveSong(id, result.folderId);
        movedCount++;
      } catch (e) {
        SyncLogger.error('[Songs] moveSong failed for $id', e);
      }
    }

    _exitSelectMode();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$movedCount song${movedCount == 1 ? '' : 's'} moved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteSelectedSongs() async {
    final count = _selectedSongIds.length;
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Move to Trash'),
            content: Text(
                'Move $count song${count == 1 ? '' : 's'} to trash?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Move to Trash'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldDelete || !mounted) return;

    final repository = ref.read(songRepositoryProvider);
    final ids = _selectedSongIds.toList();
    var deletedCount = 0;

    for (final id in ids) {
      try {
        await repository.trashSong(id);
        deletedCount++;
      } catch (e) {
        SyncLogger.error('[Songs] trashSong failed for $id', e);
      }
    }

    _exitSelectMode();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Moved $deletedCount song${deletedCount == 1 ? '' : 's'} to trash'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _FavoriteCard extends StatelessWidget {
  final String title;
  final String language;
  final bool hasChords;
  final VoidCallback onTap;

  const _FavoriteCard({
    required this.title,
    required this.language,
    required this.hasChords,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.orange.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.favorite,
                    size: 16,
                    color: Colors.red.shade400,
                  ),
                  const Spacer(),
                  if (hasChords)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Chords',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                language,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
