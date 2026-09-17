import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/folder_model.dart';
import 'package:notify/features/notes/domain/services/folder_tree_flattener.dart';

FolderModel _folder(String id, {String? parentId, String? name}) => FolderModel(
  id: id,
  parentId: parentId,
  name: name ?? id,
  type: 'note',
  userId: 'u1',
  updatedAt: 0,
  createdAt: 0,
  version: 1,
  deleted: 0,
);

List<String> _ids(List<FolderTreeRow> rows) =>
    rows.map((r) => r.folder.id).toList();

void main() {
  group('flattenFolderTree', () {
    test('collapsed roots emit only the top level', () {
      final rows = flattenFolderTree(
        folders: [
          _folder('A'),
          _folder('B'),
          _folder('A1', parentId: 'A'),
        ],
        expandedIds: const {},
        noteCountByFolderId: const {},
      );

      expect(_ids(rows), ['A', 'B']);
      expect(rows.first.hasChildren, isTrue);
      expect(rows.first.depth, 0);
    });

    test('expanding a folder nests its children one level deeper', () {
      final rows = flattenFolderTree(
        folders: [
          _folder('A'),
          _folder('A1', parentId: 'A'),
        ],
        expandedIds: const {'A'},
        noteCountByFolderId: const {},
      );

      expect(_ids(rows), ['A', 'A1']);
      expect(rows[1].depth, 1);
      expect(rows[1].hasChildren, isFalse);
    });

    test('note counts roll up through descendants', () {
      final rows = flattenFolderTree(
        folders: [
          _folder('A'),
          _folder('A1', parentId: 'A'),
          _folder('A1a', parentId: 'A1'),
        ],
        expandedIds: const {'A', 'A1'},
        noteCountByFolderId: const {'A': 1, 'A1': 2, 'A1a': 4},
      );

      expect(rows[0].totalNoteCount, 7); // own 1 + 2 + 4
      expect(rows[1].totalNoteCount, 6); // own 2 + 4
      expect(rows[2].totalNoteCount, 4);
    });

    // The bug this function exists to fix. Traversal used to start only at the
    // parentId == null folders, so a folder whose parent no longer resolves —
    // deleted on another device while this one still holds the child — was
    // unreachable and silently vanished with its whole subtree.
    test('a folder whose parent no longer exists is surfaced, not dropped', () {
      final rows = flattenFolderTree(
        folders: [
          _folder('A'),
          _folder('orphan', parentId: 'deleted-elsewhere'),
          _folder('orphanChild', parentId: 'orphan'),
        ],
        expandedIds: const {'orphan'},
        noteCountByFolderId: const {'orphanChild': 3},
      );

      expect(_ids(rows), containsAll(['orphan', 'orphanChild']));
      // The orphan is adopted at the top level, its child stays nested under it.
      final orphan = rows.firstWhere((r) => r.folder.id == 'orphan');
      final child = rows.firstWhere((r) => r.folder.id == 'orphanChild');
      expect(orphan.depth, 0);
      expect(child.depth, 1);
      // And the notes underneath it are still counted.
      expect(orphan.totalNoteCount, 3);
    });

    test('an orphaned group is adopted once, not once per member', () {
      final rows = flattenFolderTree(
        folders: [
          _folder('orphan', parentId: 'gone'),
          _folder('child', parentId: 'orphan'),
          _folder('grandchild', parentId: 'child'),
        ],
        expandedIds: const {'orphan', 'child'},
        noteCountByFolderId: const {},
      );

      expect(_ids(rows), ['orphan', 'child', 'grandchild']);
      expect(rows.map((r) => r.depth), [0, 1, 2]);
    });

    test('a parent cycle terminates and still shows every folder', () {
      final rows = flattenFolderTree(
        folders: [
          _folder('A'),
          _folder('B', parentId: 'C'),
          _folder('C', parentId: 'B'),
        ],
        expandedIds: const {'A', 'B', 'C'},
        noteCountByFolderId: const {'B': 1, 'C': 1},
      );

      // Terminates, and no folder is emitted twice.
      expect(_ids(rows), hasLength(3));
      expect(_ids(rows).toSet(), {'A', 'B', 'C'});
    });

    test('a self-parenting folder terminates and is still shown', () {
      final rows = flattenFolderTree(
        folders: [_folder('loop', parentId: 'loop')],
        expandedIds: const {'loop'},
        noteCountByFolderId: const {'loop': 2},
      );

      expect(_ids(rows), ['loop']);
      expect(rows.single.totalNoteCount, 2);
    });

    test('an empty folder list yields no rows', () {
      expect(
        flattenFolderTree(
          folders: const [],
          expandedIds: const {},
          noteCountByFolderId: const {},
        ),
        isEmpty,
      );
    });
  });
}
