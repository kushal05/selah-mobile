import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/motion_preferences.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/lists/folder_row.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../domain/services/folder_tree_flattener.dart';
import '../providers/database_provider.dart';
import '../providers/notes_home_ui_state.dart';
import '../screens/folder_management_screen.dart';

/// The collapsible folder tree at the top of the Notes screen.
///
/// Split out of `notes_home_screen.dart` so it rebuilds on its own. It watches
/// only the folder and note streams plus the three slices of view state it
/// actually draws from, so changing the sort order or opening a filter sheet
/// no longer re-runs the tree flatten and its note-count roll-up.
class FolderSection extends ConsumerWidget {
  const FolderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow watches: the tree only redraws when folders, notes or one of
    // these three slices changes.
    final ui = ref.watch(
      notesHomeUiProvider.select(
        (s) => (
          expandedFolders: s.expandedFolders,
          selectedFolderId: s.selectedFolderId,
          folderSectionExpanded: s.folderSectionExpanded,
        ),
      ),
    );
    final foldersAsync = ref.watch(foldersStreamProvider);
    final notesAsync = ref.watch(notesStreamProvider);

    return Container(
      // The folder section is part of the page, not a raised panel. A filled
      // band here reads as a grey slab across the top of the list — it was
      // Colors.grey.shade100 before, which the theme migration turned into a
      // heavier container fill.
      color: context.pageGround,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsible Header
          _header(
            context,
            ref,
            foldersAsync,
            expanded: ui.folderSectionExpanded,
          ),

          // Folder List (only visible when expanded)
          if (ui.folderSectionExpanded)
            Flexible(
              child: foldersAsync.when(
                loading: () =>
                    const ListTileSkeletonList(count: 4, hasLeading: false),
                error: (e, _) =>
                    Center(child: Text(UserFacingError.forLoad(e))),
                data: (folders) {
                  if (folders.isEmpty) {
                    return Center(
                      child: Text(
                        l10n(context).noFoldersYet,
                        style: TextStyle(color: context.mutedText),
                      ),
                    );
                  }

                  // Get notes to calculate counts per folder
                  final notes = notesAsync.valueOrNull ?? [];

                  final noteCountByFolder = <String?, int>{};
                  for (final note in notes) {
                    noteCountByFolder[note.folderId] =
                        (noteCountByFolder[note.folderId] ?? 0) + 1;
                  }

                  // Rows are data, not widgets, so itemBuilder below stays
                  // lazy. See flattenFolderTree for the orphan/cycle handling.
                  final rows = flattenFolderTree(
                    folders: folders,
                    expandedIds: ui.expandedFolders,
                    noteCountByFolderId: noteCountByFolder,
                  );

                  // "All Notes" occupies index 0; folder rows follow.
                  return ListView.builder(
                    // Sizes to its rows so the section can be shorter than
                    // the ceiling when there are only a few folders.
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return FolderRow(
                          title: l10n(context).allNotes,
                          noteCount: notes.length,
                          depth: 0,
                          hasChildren: false,
                          isExpanded: false,
                          isActive: ui.selectedFolderId == null,
                          onTap: () => ref
                              .read(notesHomeUiProvider.notifier)
                              .selectFolder(null),
                          onExpandToggle: null,
                        );
                      }
                      return _row(
                        ref,
                        rows[index - 1],
                        expandedFolders: ui.expandedFolders,
                        selectedFolderId: ui.selectedFolderId,
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Builds one already-resolved folder row. Depth, child-ness and the
  /// rolled-up note count come from [flattenFolderTree]; this only adds the
  /// selection/expansion state and the callbacks.

  /// Takes its state as parameters rather than watching.
  ///
  /// This runs from `itemBuilder`, i.e. during layout and outside `build`, so
  /// a `ref.watch` here would tear down and re-create its subscription on
  /// every rebuild — and watching the whole provider would undo the
  /// `.select(...)` above, putting the tree back on every sort and filter
  /// change.
  Widget _row(
    WidgetRef ref,
    FolderTreeRow row, {
    required Set<String> expandedFolders,
    required String? selectedFolderId,
  }) {
    final folder = row.folder;
    final isExpanded = expandedFolders.contains(folder.id);

    return FolderRow(
      title: folder.name,
      noteCount: row.totalNoteCount,
      depth: row.depth,
      hasChildren: row.hasChildren,
      isExpanded: isExpanded,
      isActive: selectedFolderId == folder.id,
      visibility: folder.visibility,
      onTap: () =>
          ref.read(notesHomeUiProvider.notifier).selectFolder(folder.id),
      onExpandToggle: row.hasChildren
          ? () {
              ref
                  .read(notesHomeUiProvider.notifier)
                  .toggleFolderExpanded(folder.id);
            }
          : null,
    );
  }

  /// Builds the notes section

  /// Takes [expanded] rather than watching, for the same reason as [_row].
  Widget _header(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<dynamic>> foldersAsync, {
    required bool expanded,
  }) {
    final theme = Theme.of(context);

    final folderCount = foldersAsync.when(
      data: (folders) => folders.length,
      loading: () => 0,
      error: (e, s) => 0,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(notesHomeUiProvider.notifier).toggleFolderSection(),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.hairline, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Expand/collapse indicator
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: context.motion(const Duration(milliseconds: 300)),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  // Carried over from the incoming branch's theme-token pass:
                  // this method was extracted into FolderSection on this side
                  // while that change landed on it there.
                  color: context.mutedText,
                ),
              ),
              const SizedBox(width: 8),
              // Title and count
              Text(
                'FOLDERS ($folderCount)',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.mutedText,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Add folder button
              IconButton(
                tooltip: l10n(context).newFolder,
                icon: Icon(
                  Icons.create_new_folder_rounded,
                  color: AppTheme.brandPurple,
                  size: 20,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FolderManagementScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a section header with title, count, and optional trailing widget
}
