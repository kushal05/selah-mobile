import '../database/sync_database.dart';
import '../sync/repositories/folder_repository.dart';
import '../sync/repositories/note_repository.dart';
import '../sync/repositories/prayer_repository.dart';

/// Seed deterministic test data into the Drift database.
///
/// Every seed method returns the IDs of created entities so tests can
/// assert against them without querying by name.
class TestSeeder {
  final SyncDatabase db;
  final FolderRepository folderRepo;
  final NoteRepository noteRepo;
  final PrayerRepository prayerRepo;

  TestSeeder({
    required this.db,
    required this.folderRepo,
    required this.noteRepo,
    required this.prayerRepo,
  });

  /// Seed [count] folders under the root, named "Folder 0", "Folder 1", ...
  ///
  /// Returns the list of created [FolderModel]s (with IDs).
  Future<List<String>> seedFolders(int count, {required String userId}) async {
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      final folder = await folderRepo.createFolder(
        name: 'Folder $i',
        userId: userId,
      );
      ids.add(folder.id);
    }
    return ids;
  }

  /// Seed [count] notes inside [folderId], named "Note 0", "Note 1", ...
  ///
  /// Returns the list of generated note IDs.
  Future<List<String>> seedNotes(
    int count, {
    required String userId,
    required String folderId,
  }) async {
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      final note = await noteRepo.createNote(
        title: 'Note $i',
        folderId: folderId,
        userId: userId,
      );
      ids.add(note.id);
    }
    return ids;
  }

  /// Seed [count] prayers with title "Prayer 0", "Prayer 1", ...
  ///
  /// Returns the list of generated prayer IDs.
  Future<List<String>> seedPrayers(
    int count, {
    required String userId,
  }) async {
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      final prayer = await prayerRepo.createPrayer(
        title: 'Prayer $i',
        userId: userId,
      );
      ids.add(prayer.id);
    }
    return ids;
  }

  /// Seed a folder tree of [depth] levels, each level having [childrenPerLevel] children.
  ///
  /// Returns a flat list of all folder IDs (root first, then children).
  Future<List<String>> seedFolderTree(
    int depth, {
    required String userId,
    String? parentId,
    int childrenPerLevel = 2,
  }) async {
    if (depth <= 0) return [];

    final ids = <String>[];
    for (var i = 0; i < childrenPerLevel; i++) {
      final folder = await folderRepo.createFolder(
        name: 'Folder-d${depth}_$i',
        userId: userId,
        parentId: parentId,
      );
      ids.add(folder.id);

      // Recurse for children
      final childIds = await seedFolderTree(
        depth - 1,
        userId: userId,
        parentId: folder.id,
        childrenPerLevel: childrenPerLevel,
      );
      ids.addAll(childIds);
    }
    return ids;
  }
}
