import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/testing/test_clock.dart';

/// Filter type for the trash screen
enum _TrashFilter { all, notes, prayers, promises, songs, people, folders, preachers, tags }

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  _TrashFilter _filter = _TrashFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'empty') _confirmEmptyTrash();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'empty',
                child: Text('Empty Trash'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _TrashFilter.values.map((f) {
                final label = f.name[0].toUpperCase() + f.name.substring(1);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Trash list
          Expanded(child: _buildTrashList()),
        ],
      ),
    );
  }

  Widget _buildTrashList() {
    final items = <_TrashItem>[];

    // Collect trashed items based on filter
    if (_filter == _TrashFilter.all || _filter == _TrashFilter.notes) {
      final notes = ref.watch(trashedNotesStreamProvider);
      notes.whenData((list) {
        for (final n in list) {
          items.add(_TrashItem(
            id: n.id,
            title: n.title.isEmpty ? 'Untitled Note' : n.title,
            icon: Icons.note_outlined,
            type: 'Note',
            trashedAt: n.trashedAt ?? 0,
            onRestore: () => _restore(() => ref.read(noteRepositoryProvider).restoreNote(n.id)),
            onDelete: () => _confirmPermanentDelete(
              n.title.isEmpty ? 'Untitled Note' : n.title,
              () => ref.read(noteRepositoryProvider).deleteNote(n.id),
            ),
          ));
        }
      });
    }

    if (_filter == _TrashFilter.all || _filter == _TrashFilter.folders) {
      final folders = ref.watch(trashedFoldersStreamProvider);
      folders.whenData((list) {
        for (final f in list) {
          items.add(_TrashItem(
            id: f.id,
            title: f.name,
            icon: Icons.folder_outlined,
            type: 'Folder',
            trashedAt: f.trashedAt ?? 0,
            onRestore: () => _restore(() => ref.read(folderRepositoryProvider).restoreFromTrash(f.id)),
            onDelete: () => _confirmPermanentDelete(
              f.name,
              () => ref.read(folderRepositoryProvider).deleteFolder(f.id),
            ),
          ));
        }
      });
    }

    if (_filter == _TrashFilter.all || _filter == _TrashFilter.prayers) {
      final prayers = ref.watch(trashedPrayersStreamProvider);
      prayers.whenData((list) {
        for (final p in list) {
          items.add(_TrashItem(
            id: p.id,
            title: p.title,
            icon: Icons.favorite_outline,
            type: 'Prayer',
            trashedAt: p.trashedAt ?? 0,
            onRestore: () => _restore(() => ref.read(prayerRepositoryProvider).restorePrayer(p.id)),
            onDelete: () => _confirmPermanentDelete(
              p.title,
              () => ref.read(prayerRepositoryProvider).deletePrayer(p.id),
            ),
          ));
        }
      });
    }

    if (_filter == _TrashFilter.all || _filter == _TrashFilter.promises) {
      final promises = ref.watch(trashedPromisesStreamProvider);
      promises.whenData((list) {
        for (final p in list) {
          final title = p.reference;
          items.add(_TrashItem(
            id: p.id,
            title: title,
            icon: Icons.menu_book_outlined,
            type: 'Promise',
            trashedAt: p.trashedAt ?? 0,
            onRestore: () => _restore(() => ref.read(promiseRepositoryProvider).restorePromise(p.id)),
            onDelete: () => _confirmPermanentDelete(
              title,
              () => ref.read(promiseRepositoryProvider).deletePromise(p.id),
            ),
          ));
        }
      });
    }

    if (_filter == _TrashFilter.all || _filter == _TrashFilter.songs) {
      final songs = ref.watch(trashedSongsStreamProvider);
      songs.whenData((list) {
        for (final s in list) {
          items.add(_TrashItem(
            id: s.id,
            title: s.title,
            icon: Icons.music_note_outlined,
            type: 'Song',
            trashedAt: s.trashedAt ?? 0,
            onRestore: () => _restore(() => ref.read(songRepositoryProvider).restoreSong(s.id)),
            onDelete: () => _confirmPermanentDelete(
              s.title,
              () => ref.read(songRepositoryProvider).deleteSong(s.id),
            ),
          ));
        }
      });
    }

    if (_filter == _TrashFilter.all || _filter == _TrashFilter.people) {
      final people = ref.watch(trashedPeopleStreamProvider);
      people.whenData((list) {
        for (final p in list) {
          items.add(_TrashItem(
            id: p.id,
            title: p.name,
            icon: Icons.person_outlined,
            type: 'Person',
            trashedAt: p.trashedAt ?? 0,
            onRestore: () => _restore(() => ref.read(personRepositoryProvider).restorePerson(p.id)),
            onDelete: () => _confirmPermanentDelete(
              p.name,
              () => ref.read(personRepositoryProvider).deletePerson(p.id),
            ),
          ));
        }
      });
    }

    if (_filter == _TrashFilter.all || _filter == _TrashFilter.preachers) {
      final preachers = ref.watch(trashedPreachersStreamProvider);
      preachers.whenData((list) {
        for (final p in list) {
          items.add(_TrashItem(
            id: p.id,
            title: p.name,
            icon: Icons.mic_outlined,
            type: 'Preacher',
            trashedAt: p.trashedAt ?? 0,
            onRestore: () => _restore(() => ref.read(preacherRepositoryProvider).restorePreacher(p.id)),
            onDelete: () => _confirmPermanentDelete(
              p.name,
              () => ref.read(preacherRepositoryProvider).deletePreacher(p.id),
            ),
          ));
        }
      });
    }

    if (_filter == _TrashFilter.all || _filter == _TrashFilter.tags) {
      final tags = ref.watch(trashedTagsStreamProvider);
      tags.whenData((list) {
        for (final t in list) {
          items.add(_TrashItem(
            id: t.id,
            title: t.name,
            icon: Icons.label_outline,
            type: 'Tag',
            trashedAt: t.trashedAt ?? 0,
            onRestore: () => _restore(() => ref.read(tagRepositoryProvider).restoreTag(t.id)),
            onDelete: () => _confirmPermanentDelete(
              t.name,
              () => ref.read(tagRepositoryProvider).deleteTag(t.id),
            ),
          ));
        }
      });
    }

    // Sort by most recently trashed
    items.sort((a, b) => b.trashedAt.compareTo(a.trashedAt));

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Trash is empty',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildTrashTile(items[index]),
    );
  }

  Widget _buildTrashTile(_TrashItem item) {
    final daysLeft = 30 - ((TestClock.now() - item.trashedAt) / (24 * 60 * 60 * 1000)).floor();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(item.icon, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.type} \u2022 ${daysLeft > 0 ? '$daysLeft days left' : 'Expiring soon'}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.restore, size: 20),
              tooltip: 'Restore',
              onPressed: item.onRestore,
            ),
            IconButton(
              icon: Icon(Icons.delete_forever, size: 20, color: Colors.red.shade400),
              tooltip: 'Delete permanently',
              onPressed: item.onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restore(Future<void> Function() action) async {
    await action();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restored'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmPermanentDelete(String title, Future<void> Function() action) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Permanently'),
        content: Text('"$title" will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await action();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Permanently deleted'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }

  void _confirmEmptyTrash() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Trash'),
        content: const Text('All items in trash will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final noteRepo = ref.read(noteRepositoryProvider);
              final folderRepo = ref.read(folderRepositoryProvider);
              final prayerRepo = ref.read(prayerRepositoryProvider);
              final promiseRepo = ref.read(promiseRepositoryProvider);
              final personRepo = ref.read(personRepositoryProvider);
              final songRepo = ref.read(songRepositoryProvider);
              final preacherRepo = ref.read(preacherRepositoryProvider);
              final tagRepo = ref.read(tagRepositoryProvider);
              final userId = ref.read(currentUserIdProvider);

              final trashedNotes = await noteRepo.getTrashedNotes(userId);
              for (final n in trashedNotes) {
                await noteRepo.deleteNote(n.id);
              }

              final trashedFolders = await folderRepo.getTrashedFolders(userId);
              for (final f in trashedFolders) {
                await folderRepo.deleteFolder(f.id);
              }

              final trashedPrayers = await prayerRepo.getTrashedPrayers(userId);
              for (final p in trashedPrayers) {
                await prayerRepo.deletePrayer(p.id);
              }

              final trashedPromises = await promiseRepo.getTrashedPromises(userId);
              for (final p in trashedPromises) {
                await promiseRepo.deletePromise(p.id);
              }

              final trashedPeople = await personRepo.getTrashedPeople(userId);
              for (final p in trashedPeople) {
                await personRepo.deletePerson(p.id);
              }

              final trashedSongs = await songRepo.getTrashedSongs(userId);
              for (final s in trashedSongs) {
                await songRepo.deleteSong(s.id);
              }

              final trashedPreachers = await preacherRepo.getTrashedPreachers(userId);
              for (final p in trashedPreachers) {
                await preacherRepo.deletePreacher(p.id);
              }

              final trashedTags = await tagRepo.getTrashedTags(userId);
              for (final t in trashedTags) {
                await tagRepo.deleteTag(t.id);
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Trash emptied'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text('Empty Trash', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }
}

class _TrashItem {
  final String id;
  final String title;
  final IconData icon;
  final String type;
  final int trashedAt;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _TrashItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.type,
    required this.trashedAt,
    required this.onRestore,
    required this.onDelete,
  });
}
