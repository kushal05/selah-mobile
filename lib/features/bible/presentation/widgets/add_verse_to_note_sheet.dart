import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/drag_handle.dart';
import '../../../notes/domain/models/note.dart';
import '../../../notes/presentation/providers/database_provider.dart';

/// Where the verse goes: a brand-new note, or one that already exists.
class VerseNoteTarget {
  /// The chosen note, or null for a new one.
  final Note? note;

  const VerseNoteTarget.newNote() : note = null;
  const VerseNoteTarget.existing(Note this.note);
}

/// "Add to notes" from the verse sheet: a new note, or pick one of the
/// existing notes (most recently updated first).
class AddVerseToNoteSheet extends ConsumerWidget {
  const AddVerseToNoteSheet({super.key});

  static Future<VerseNoteTarget?> show(BuildContext context) {
    return showModalBottomSheet<VerseNoteTarget>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const AddVerseToNoteSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = l10n(context);
    final theme = Theme.of(context);
    final notes = ref.watch(notesStreamProvider);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: DragHandle()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              t.addToNotes,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.note_add_outlined),
            title: Text(t.newNote),
            onTap: () => Navigator.of(context).pop(const VerseNoteTarget.newNote()),
          ),
          Divider(height: 1, color: context.hairline),
          Flexible(
            child: notes.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(UserFacingError.forLoad(e)),
              ),
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            t.existingNotes,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final note in list)
                          ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: Text(
                              note.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.of(context)
                                .pop(VerseNoteTarget.existing(note)),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
