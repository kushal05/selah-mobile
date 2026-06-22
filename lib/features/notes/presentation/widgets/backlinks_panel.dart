import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/database_provider.dart';

/// Collapsible panel that shows other notes referencing the current note.
/// Drop into the bottom of a note detail screen. Hidden when there are no
/// backlinks so the UI stays quiet for new/leaf notes.
class BacklinksPanel extends ConsumerWidget {
  final String noteId;
  const BacklinksPanel({super.key, required this.noteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final backlinksAsync = ref.watch(noteBacklinksProvider(noteId));

    return backlinksAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (links) {
        if (links.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Row(
              children: [
                Icon(Icons.link, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Linked from ${links.length} note${links.length == 1 ? '' : 's'}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            children: links
                .map((b) => _BacklinkTile(
                      noteId: b.noteId,
                      title: b.noteTitle,
                      snippet: b.snippet,
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

class _BacklinkTile extends StatelessWidget {
  final String noteId;
  final String title;
  final String snippet;

  const _BacklinkTile({
    required this.noteId,
    required this.title,
    required this.snippet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.description_outlined, size: 20),
      title: Text(
        title.isEmpty ? 'Untitled' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        _cleanSnippet(snippet),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      onTap: () => context.push('/notes/$noteId'),
    );
  }

  // FTS snippet uses « » highlight markers — render as plain text for now.
  String _cleanSnippet(String s) =>
      s.replaceAll('«', '').replaceAll('»', '').trim();
}
