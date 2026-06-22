import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/note_template.dart';
import '../providers/database_provider.dart';

/// Bottom-sheet picker for selecting a [NoteTemplate]. On selection, creates
/// a seeded note via the notes repository and navigates to its detail page.
///
/// Use [showNoteTemplatePicker] rather than constructing this directly.
class NoteTemplatePickerSheet extends ConsumerWidget {
  final String? folderId;
  const NoteTemplatePickerSheet({super.key, this.folderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Start with a template',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: builtInNoteTemplates.length,
              separatorBuilder: (_, _) => const Divider(height: 0),
              itemBuilder: (context, i) {
                final template = builtInNoteTemplates[i];
                return ListTile(
                  leading: Icon(template.icon),
                  title: Text(template.name),
                  subtitle: Text(template.description),
                  onTap: () => _onSelect(context, ref, template),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSelect(
    BuildContext context,
    WidgetRef ref,
    NoteTemplate template,
  ) async {
    final repository = ref.read(notesRepositoryProvider);
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);

    final note = template.buildNote(folderId: folderId);
    try {
      await repository.createNote(note);
    } catch (e) {
      if (!context.mounted) return;
      navigator.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create note: $e')),
      );
      return;
    }

    if (!context.mounted) return;
    navigator.pop();
    router.push('/notes/${note.id}');
  }
}

/// Open the template picker as a modal bottom sheet. Returns when the sheet
/// closes (whether by selection or cancel).
Future<void> showNoteTemplatePicker(
  BuildContext context, {
  String? folderId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => NoteTemplatePickerSheet(folderId: folderId),
  );
}
