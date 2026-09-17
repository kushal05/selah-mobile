import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/memory_verse.dart';
import '../providers/memory_verse_providers.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../l10n/l10n.dart';

/// Home for scripture memorization: lists all cards, surfaces the due count,
/// links into the review session, and opens an add-card sheet.
class MemorizationScreen extends ConsumerWidget {
  const MemorizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versesAsync = ref.watch(memoryVersesStreamProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n(context).memorization)),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        onPressed: () => _showAddSheet(context, ref),
        child: const Icon(Icons.add),
      ),
      body: versesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
        data: (verses) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final dueCount = verses.where((v) => v.dueAt <= now).length;

          if (verses.isEmpty) {
            return _Empty(onAdd: () => _showAddSheet(context, ref));
          }

          return Column(
            children: [
              if (dueCount > 0)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ElevatedButton.icon(
                    onPressed: () => context.push('/bible/memorization/review'),
                    icon: const Icon(Icons.psychology_outlined),
                    label: Text(
                      'Review $dueCount due',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: verses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final v = verses[i];
                    return _VerseCard(
                      verse: v,
                      onDelete: () =>
                          ref.read(memoryVerseRepositoryProvider).remove(v.id),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => _AddVerseSheet(
        onSave: (reference, text, version) async {
          final verse = MemoryVerse.create(
            id: const Uuid().v4(),
            reference: reference,
            text: text,
            version: version,
          );
          await ref.read(memoryVerseRepositoryProvider).upsert(verse);
          ref.invalidate(dueMemoryVersesProvider);
        },
      ),
    );
  }
}

class _VerseCard extends StatelessWidget {
  final MemoryVerse verse;
  final VoidCallback onDelete;
  const _VerseCard({required this.verse, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueText = verse.isDue
        ? 'Due now'
        : 'Next: ${_formatDue(verse.dueAt)}';
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          verse.reference,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (verse.version.isNotEmpty)
                        Text(
                          verse.version,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    verse.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dueText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Step ${verse.reviewCount}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n(context).actionDelete,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDue(int ms) {
    final now = DateTime.now();
    final due = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = due.difference(now);
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'soon';
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_outlined,
              size: 48,
              color: theme.disabledColor,
            ),
            const SizedBox(height: 12),
            Text(
              l10n(context).noMemoryVersesYet,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              l10n(context).addAVerseAndReviewItAcrossSpacedIntervals137,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n(context).addYourFirstVerse),
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

/// The add-a-verse sheet.
///
/// A StatefulWidget so the three TextEditingControllers belong to a State and
/// are disposed when the sheet leaves the tree.
///
/// Creating them in the caller and disposing them in a `finally` after
/// `await showModalBottomSheet(...)` does not work, though it looks like it
/// should: that future resolves on the *first frame of the pop animation*,
/// while the TextFields are still mounted, so they then read a disposed
/// controller and the framework throws "A TextEditingController was used
/// after being disposed". Owning them here ties their lifetime to the widget
/// that actually uses them.
class _AddVerseSheet extends StatefulWidget {
  final Future<void> Function(String reference, String text, String version)
  onSave;

  const _AddVerseSheet({required this.onSave});

  @override
  State<_AddVerseSheet> createState() => _AddVerseSheetState();
}

class _AddVerseSheetState extends State<_AddVerseSheet> {
  final _reference = TextEditingController();
  final _text = TextEditingController();
  final _version = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    _text.dispose();
    _version.dispose();
    super.dispose();
  }

  /// Guards against a second tap landing while the first save is in flight.
  /// Without it a double-tap inserts the verse twice and pops twice, and the
  /// second pop takes MemorizationScreen down with the sheet.
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    if (_reference.text.trim().isEmpty || _text.text.trim().isEmpty) return;

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final failureMessage = l10n(context).couldNotSaveVerse;
    try {
      await widget.onSave(
        _reference.text.trim(),
        _text.text.trim(),
        _version.text.trim(),
      );
    } catch (e) {
      // onPressed drops this future, so rethrowing here reached nobody: the
      // sheet simply stayed open with the fields still filled, identical to
      // not having tapped Save. Tell the reader instead, and leave their text
      // in place so the retry costs them nothing.
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
      return;
    }
    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Keeps the sheet's last control clear of the gesture bar.
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n(context).newMemoryVerse,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: InputDecoration(
                labelText: l10n(context).referenceEGJohn316,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _version,
              decoration: InputDecoration(
                labelText: l10n(context).translationOptional,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n(context).verseText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n(context).actionSave),
            ),
          ],
        ),
      ),
    );
  }
}
