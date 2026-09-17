import '../../../../core/sync/models/folder_model.dart';

/// One visible row of the folder tree, resolved to exactly what the row needs
/// in order to draw itself.
class FolderTreeRow {
  /// The folder this row represents.
  final FolderModel folder;

  /// Nesting depth, 0 for a top-level folder.
  final int depth;

  /// Whether this folder has any children at all (drives the expand chevron,
  /// independently of whether it is currently expanded).
  final bool hasChildren;

  /// This folder's own notes plus every descendant's.
  final int totalNoteCount;

  const FolderTreeRow({
    required this.folder,
    required this.depth,
    required this.hasChildren,
    required this.totalNoteCount,
  });
}

/// Flattens [folders] into the rows that are visible given [expandedIds].
///
/// Returns data rather than widgets so the caller can build rows lazily inside
/// an `itemBuilder`. The previous inline version materialised a
/// `List<Widget>` of the entire tree and then handed it to `ListView.builder`,
/// which removed the laziness that widget exists for and re-ran the whole
/// grouping, sort and roll-up on every rebuild of the screen.
///
/// Two correctness properties this guarantees that the inline version did not:
///
/// * **No folder disappears.** Traversal used to begin only at the
///   `parentId == null` folders. Each folder has exactly one parent, so any
///   folder whose parent chain never reaches null is unreachable from those
///   roots — and it, plus its whole subtree, silently vanished from the tree
///   along with the only route to their notes. That is reachable in practice:
///   deleting a folder locally cascades to its descendants, but sync does not,
///   so a folder deleted on one device while a child is created on another
///   leaves that child with a parent id that no longer resolves.
///   [_resolveRoot] gives every folder a display root, so an orphaned group
///   surfaces at the top level instead.
///
/// * **Cycles terminate.** A parent cycle (`A → B → A`) is pathological but
///   not impossible across two devices reparenting concurrently. Each folder
///   is emitted at most once and the roll-up refuses to re-enter a folder it
///   is already counting, so neither recursion can run away.
List<FolderTreeRow> flattenFolderTree({
  required List<FolderModel> folders,
  required Set<String> expandedIds,
  required Map<String?, int> noteCountByFolderId,
}) {
  if (folders.isEmpty) return const [];

  final byId = {for (final folder in folders) folder.id: folder};

  final childrenByParentId = <String?, List<FolderModel>>{};
  for (final folder in folders) {
    childrenByParentId.putIfAbsent(folder.parentId, () => []).add(folder);
  }
  for (final children in childrenByParentId.values) {
    children.sort((a, b) => a.name.compareTo(b.name));
  }

  const noChildren = <FolderModel>[];

  // Roll-up of a folder's own notes plus all descendants'. Memoised, because
  // a folder's total is otherwise recomputed once per ancestor.
  final totalById = <String, int>{};
  final counting = <String>{};
  int rollUp(FolderModel folder) {
    final cached = totalById[folder.id];
    if (cached != null) return cached;
    // Already on the stack: a cycle. Contribute nothing rather than recurse.
    if (!counting.add(folder.id)) return 0;
    var count = noteCountByFolderId[folder.id] ?? 0;
    for (final child in childrenByParentId[folder.id] ?? noChildren) {
      count += rollUp(child);
    }
    totalById[folder.id] = count;
    return count;
  }

  // Every folder resolves to the top of its own group, so nothing is orphaned.
  final rootIds = <String>{};
  final roots = <FolderModel>[];
  for (final folder in folders) {
    final root = _resolveRoot(folder, byId);
    if (rootIds.add(root.id)) roots.add(root);
  }
  roots.sort((a, b) => a.name.compareTo(b.name));

  final rows = <FolderTreeRow>[];
  final placed = <String>{};

  void emit(FolderModel folder, int depth) {
    if (!placed.add(folder.id)) return;
    final children = childrenByParentId[folder.id] ?? noChildren;
    rows.add(
      FolderTreeRow(
        folder: folder,
        depth: depth,
        hasChildren: children.isNotEmpty,
        totalNoteCount: rollUp(folder),
      ),
    );
    if (!expandedIds.contains(folder.id)) return;
    for (final child in children) {
      emit(child, depth + 1);
    }
  }

  for (final root in roots) {
    emit(root, 0);
  }

  return rows;
}

/// Walks up from [folder] to the top of its group.
///
/// Returns the folder itself when it has no parent (a real root), when its
/// parent id does not resolve (an orphan left behind by a delete that synced
/// without its children), or when the chain re-enters a folder already walked
/// (a parent cycle).
FolderModel _resolveRoot(FolderModel folder, Map<String, FolderModel> byId) {
  var current = folder;
  final walked = <String>{current.id};
  while (true) {
    final parentId = current.parentId;
    if (parentId == null) return current;
    final parent = byId[parentId];
    if (parent == null) return current;
    if (!walked.add(parent.id)) return current;
    current = parent;
  }
}
