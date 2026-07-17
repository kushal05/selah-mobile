import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import 'dart:convert';

import '../../../bible/presentation/providers/bible_providers.dart';
import '../../../bible/domain/models/bible_reference.dart';
import '../../domain/models/block_type.dart';
import '../../domain/models/editor_block.dart';
import '../../data/converters/markdown_block_converter.dart';
import '../../domain/models/note.dart' as domain;
import '../../domain/models/note_section.dart';
import '../../domain/models/note_table.dart';
import '../widgets/editor/note_table_widget.dart';
import '../providers/database_provider.dart';
import '../../../../shared/widgets/dialogs/move_to_folder_sheet.dart';
import '../../../../shared/widgets/lists/metadata_row.dart';
import '../widgets/backlinks_panel.dart';
import '../widgets/editor/bible_reference_block_widget.dart';
import '../widgets/editor/formatted_text_span.dart';
import 'note_editor_screen.dart';
import 'note_version_history_screen.dart';
import 'note_activity_screen.dart';
import '../providers/note_attribution_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Provider to watch a single note by ID
final noteDetailProvider =
    StreamProvider.family<domain.Note?, String>((ref, noteId) {
  final repository = ref.watch(notesRepositoryProvider);
  return repository.watchNoteById(noteId);
});


/// Note detail screen - displays a read-only view of a note
class NoteDetailScreen extends ConsumerWidget {
  final String noteId;

  const NoteDetailScreen({super.key, required this.noteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteAsync = ref.watch(noteDetailProvider(noteId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NoteEditorScreen(noteId: noteId),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showOptionsMenu(context, ref);
            },
          ),
        ],
      ),
      body: noteAsync.when(
        loading: () => const DetailPageSkeleton(),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Error loading note: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(noteDetailProvider(noteId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (note) {
          if (note == null) {
            return const Center(
              child: Text('Note not found'),
            );
          }
          return _buildNoteContent(context, ref, note);
        },
      ),
    );
  }

  Widget _buildNoteContent(BuildContext context, WidgetRef ref, domain.Note note) {
    final theme = Theme.of(context);
    final preacherName = note.preacherId != null
        ? ref.watch(personByIdProvider(note.preacherId!)).whenOrNull(data: (p) => p?.name)
        : null;

    // Foreign-edit attributions — empty map for non-owners (endpoint is
    // owner-only today) or during the async load.
    final attributions = ref
            .watch(noteBlockAttributionsProvider(noteId))
            .valueOrNull ??
        const <String, BlockAttribution>{};

    Widget blockWithAttribution(EditorBlock block) {
      final inner = _buildBlock(context, ref, block, note.document);
      final attr = attributions[block.id];
      if (attr == null) return inner;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          inner,
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: _AttributionBadge(attribution: attr),
          ),
        ],
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metadata row
            MetadataRow(
              date: _formatDate(note.noteDate ?? note.createdAt),
              preacher: preacherName,
            ),
            const SizedBox(height: 16),

            // Note title
            Text(
              note.title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Main section blocks
            ...note.document.getBlocksForSection(NoteSection.main)
                .map(blockWithAttribution),

            // Personal Application section
            if (!note.document.isSectionEmpty(NoteSection.personalApplication)) ...[
              _buildSectionHeader(context, NoteSection.personalApplication),
              ...note.document.getBlocksForSection(NoteSection.personalApplication)
                  .map(blockWithAttribution),
            ],

            // Prayer section
            if (!note.document.isSectionEmpty(NoteSection.prayer)) ...[
              _buildSectionHeader(context, NoteSection.prayer),
              ...note.document.getBlocksForSection(NoteSection.prayer)
                  .map(blockWithAttribution),
            ],

            // Backlinks — collapsed by default; renders nothing if no other
            // notes reference this one. Search is local-only (FTS + LIKE).
            BacklinksPanel(noteId: noteId),
          ],
        ),
      ),
    );
  }

  /// Render a block's text with its inline formatting (bold/italic/etc.)
  /// applied. Links are tappable here (unlike in the editor, where a tap places
  /// the caret); [FormattedText] owns the gesture recognizers' lifecycle.
  Widget _formattedText(EditorBlock block, TextStyle? style) {
    return FormattedText(
      text: block.content,
      formats: block.formats,
      style: style,
      onLinkTap: _openLink,
    );
  }

  Future<void> _openLink(String url) async {
    // Link targets can arrive from a pasted or SHARED note, so treat them as
    // untrusted: only hand well-formed, known-safe schemes to the OS. Without
    // this, a shared note could carry javascript:/intent:/file: targets.
    if (!isSafeNoteLink(url)) return;
    final uri = Uri.parse(url.trim());
    // Best effort: an unlaunchable link must never throw into the widget tree.
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Ignored — nothing sensible to show for a bad link in a note.
    }
  }

  Widget _buildBlock(BuildContext context, WidgetRef ref, EditorBlock block, dynamic document) {
    final theme = Theme.of(context);
    final indent = block.indentLevel * 24.0;

    switch (block.type) {
      case BlockType.heading1:
        return Padding(
          padding: EdgeInsets.only(left: indent, top: 16, bottom: 8),
          child: _formattedText(
            block,
            theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case BlockType.heading2:
        return Padding(
          padding: EdgeInsets.only(left: indent, top: 12, bottom: 6),
          child: _formattedText(
            block,
            theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case BlockType.heading3:
        return Padding(
          padding: EdgeInsets.only(left: indent, top: 8, bottom: 4),
          child: _formattedText(
            block,
            theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case BlockType.paragraph:
        if (block.content.isEmpty) {
          return const SizedBox(height: 12);
        }
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 8),
          child: _formattedText(block, theme.textTheme.bodyLarge),
        );

      case BlockType.bulletList:
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8, right: 8),
                child: Icon(Icons.circle, size: 6),
              ),
              Expanded(
                child: _formattedText(block, theme.textTheme.bodyLarge),
              ),
            ],
          ),
        );

      case BlockType.numberedList:
        final number = document.calculateListNumber(block.id);
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$number.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              Expanded(
                child: _formattedText(block, theme.textTheme.bodyLarge),
              ),
            ],
          ),
        );

      case BlockType.checkbox:
        final isChecked = block.isChecked == true;
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 4),
          child: InkWell(
            onTap: () async {
              await ref.read(notesRepositoryProvider).toggleCheckboxBlock(noteId, block.id);
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: isChecked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _formattedText(
                    block,
                    theme.textTheme.bodyLarge?.copyWith(
                      decoration: isChecked ? TextDecoration.lineThrough : null,
                      color: isChecked
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case BlockType.quote:
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 8),
          child: Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                  width: 3,
                ),
              ),
            ),
            child: _formattedText(
              block,
              theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
        );

      case BlockType.code:
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _formattedText(
              block,
              theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: kMonospaceFallback,
              ),
            ),
          ),
        );

      case BlockType.table:
        NoteTable table;
        try {
          table = NoteTable.fromJson(
              jsonDecode(block.content) as Map<String, dynamic>);
        } catch (_) {
          table = NoteTable.empty;
        }
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 8),
          child: NoteTableWidget(table: table, onLinkTap: _openLink),
        );

      case BlockType.bibleReference:
        BibleReference reference;
        try {
          final contentMap = jsonDecode(block.content) as Map<String, dynamic>;
          reference = BibleReference.fromJson(contentMap);
        } catch (_) {
          reference = BibleReference.empty();
        }
        final needsLookup = reference.text.isEmpty && !reference.pending;
        final resolved = needsLookup
            ? reference.copyWith(
                text: ref.watch(verseLookupProvider(reference.reference)))
            : reference;
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 4),
          child: BibleReferenceBlockWidget(reference: resolved),
        );
    }
  }

  Widget _buildSectionHeader(BuildContext context, NoteSection section) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 12),
          Text(
            section.displayTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showOptionsMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(sheetContext);
                _shareNote(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Copy as Markdown'),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyAsMarkdown(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.pop(sheetContext);
                _duplicateNote(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to folder'),
              onTap: () {
                Navigator.pop(sheetContext);
                _moveNoteToFolder(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Version History'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteVersionHistoryScreen(noteId: noteId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('Activity'),
              subtitle: const Text('Who edited or viewed'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteActivityScreen(noteId: noteId),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Theme.of(sheetContext).colorScheme.error),
              title: Text('Move to Trash', style: TextStyle(color: Theme.of(sheetContext).colorScheme.error)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await _showDeleteConfirmation(context);
                if (confirmed && context.mounted) {
                  final repository = ref.read(notesRepositoryProvider);
                  await repository.trashNote(noteId);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _shareNote(BuildContext context, WidgetRef ref) {
    final note = ref.read(noteDetailProvider(noteId)).valueOrNull;
    if (note == null) return;

    final buffer = StringBuffer();
    buffer.writeln(note.title);
    buffer.writeln();

    for (final block in note.document.blocks) {
      switch (block.type) {
        case BlockType.heading1:
        case BlockType.heading2:
        case BlockType.heading3:
          buffer.writeln(block.content);
          buffer.writeln();
        case BlockType.paragraph:
          if (block.content.isNotEmpty) {
            buffer.writeln(block.content);
          } else {
            buffer.writeln();
          }
        case BlockType.bulletList:
          buffer.writeln('  • ${block.content}');
        case BlockType.numberedList:
          buffer.writeln('  ${note.document.calculateListNumber(block.id)}. ${block.content}');
        case BlockType.checkbox:
          final check = block.isChecked == true ? '✓' : '○';
          buffer.writeln('  [$check] ${block.content}');
        case BlockType.quote:
          buffer.writeln('  ▏${block.content}');
        case BlockType.code:
          buffer.writeln(block.content);
        case BlockType.table:
          // `content` is JSON — share the cell text, never the raw payload.
          try {
            final table = NoteTable.fromJson(
                jsonDecode(block.content) as Map<String, dynamic>);
            for (final row in table.rows) {
              buffer.writeln(row.map((c) => c.text).join('  |  '));
            }
          } catch (_) {
            buffer.writeln('[Table]');
          }
        case BlockType.bibleReference:
          try {
            final contentMap = jsonDecode(block.content) as Map<String, dynamic>;
            final bibleRef = BibleReference.fromJson(contentMap);
            buffer.writeln(bibleRef.displayReference);
            final fullText = bibleRef.fullText;
            if (fullText.isNotEmpty) buffer.writeln(fullText);
          } catch (_) {
            buffer.writeln('[Bible Reference]');
          }
      }
    }

    buffer.writeln();
    buffer.write(Routes.noteDeepLink(noteId));
    Share.share(buffer.toString().trimRight(), subject: note.title);
  }

  void _copyAsMarkdown(BuildContext context, WidgetRef ref) {
    final note = ref.read(noteDetailProvider(noteId)).valueOrNull;
    if (note == null) return;

    final buffer = StringBuffer();
    if (note.title.isNotEmpty) {
      buffer.writeln('# ${note.title}');
      buffer.writeln();
    }
    buffer.write(MarkdownBlockConverter.toMarkdown(note.document.blocks));

    Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied as Markdown'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _moveNoteToFolder(BuildContext context, WidgetRef ref) async {
    final note = ref.read(noteDetailProvider(noteId)).valueOrNull;
    if (note == null) return;

    final result = await MoveToFolderSheet.show(
      context,
      currentFolderId: note.folderId,
      noteCount: 1,
    );
    if (result == null || !context.mounted) return;

    final repository = ref.read(notesRepositoryProvider);
    final moved = await repository.moveNotes([noteId], result.targetFolderId);
    if (context.mounted && moved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to ${result.targetFolderName}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _duplicateNote(BuildContext context, WidgetRef ref) async {
    final note = ref.read(noteDetailProvider(noteId)).valueOrNull;
    if (note == null) return;

    try {
      final repository = ref.read(notesRepositoryProvider);
      final newNote = domain.Note.create(
        id: const Uuid().v4(),
        title: '${note.title} (copy)',
        document: note.document,
      );
      await repository.createNote(newNote);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note duplicated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error duplicating note: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Move to Trash'),
            content: const Text('Are you sure you want to move this note to trash?'),
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
}

/// Small inline pill showing "edited by X" under a block that was last
/// modified by a user other than the current viewer. Kept compact so it
/// doesn't visually compete with the block content.
class _AttributionBadge extends StatelessWidget {
  final BlockAttribution attribution;
  const _AttributionBadge({required this.attribution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        'edited by ${attribution.readableName}',
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
