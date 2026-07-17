import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/models/note_block_model.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../domain/models/note_revision.dart';
import '../providers/database_provider.dart';

/// Screen that shows a side-by-side comparison between a revision and the
/// current note state.
///
/// Uses simple text comparison — highlights blocks that were added, removed,
/// or changed between the two versions.
class RevisionDiffView extends ConsumerStatefulWidget {
  final String noteId;
  final NoteRevisionSnapshot revision;

  const RevisionDiffView({
    super.key,
    required this.noteId,
    required this.revision,
  });

  @override
  ConsumerState<RevisionDiffView> createState() => _RevisionDiffViewState();
}

class _RevisionDiffViewState extends ConsumerState<RevisionDiffView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currentBlocksAsync =
        ref.watch(currentNoteBlocksProvider(widget.noteId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Versions'),
      ),
      body: currentBlocksAsync.when(
        loading: () => const DetailPageSkeleton(),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: cs.error),
                const SizedBox(height: 12),
                Text(
                  'Couldn\'t load current blocks',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  onPressed: () => ref
                      .invalidate(currentNoteBlocksProvider(widget.noteId)),
                ),
              ],
            ),
          ),
        ),
        data: (currentBlocks) {
          final revisionData = widget.revision.deserialize();
          if (revisionData == null) {
            return Center(
              child: Text(
                'Unable to read this revision.',
                style: TextStyle(color: cs.error),
              ),
            );
          }
          final revisionBlocks = revisionData.blocks;

          final diffLines = _computeDiff(revisionBlocks, currentBlocks);

          return Column(
            children: [
              // Legend
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: cs.surfaceContainerLow,
                child: Row(
                  children: [
                    _LegendChip(
                        color: Colors.red.shade50,
                        borderColor: Colors.red.shade200,
                        label: 'Removed'),
                    const SizedBox(width: 12),
                    _LegendChip(
                        color: Colors.green.shade50,
                        borderColor: Colors.green.shade200,
                        label: 'Added'),
                    const SizedBox(width: 12),
                    _LegendChip(
                        color: Colors.amber.shade50,
                        borderColor: Colors.amber.shade200,
                        label: 'Changed'),
                    const Spacer(),
                    Text(
                      '${diffLines.length} differences',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Header row
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Previous',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Current',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Diff body
              Expanded(
                child: diffLines.isEmpty
                    ? Center(
                        child: Text(
                          'No differences found',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: diffLines.length,
                        itemBuilder: (context, index) {
                          return _DiffRow(diff: diffLines[index]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Compute a diff between revision blocks and current blocks using block ID
  /// matching. This handles insertions/deletions in the middle correctly,
  /// unlike positional index comparison.
  static List<_DiffLine> _computeDiff(
    List<NoteBlockModel> revisionBlocks,
    List<NoteBlockModel> currentBlocks,
  ) {
    final curById = {for (final b in currentBlocks) b.id: b.displayText};
    final result = <_DiffLine>[];
    final matched = <String>{};

    // Walk revision blocks: find changed or removed blocks.
    for (final block in revisionBlocks) {
      final revText = block.displayText;
      if (curById.containsKey(block.id)) {
        matched.add(block.id);
        final curText = curById[block.id]!;
        if (revText != curText) {
          result.add(_DiffLine(
              type: _DiffType.changed, oldText: revText, newText: curText));
        }
      } else {
        result.add(_DiffLine(
            type: _DiffType.removed, oldText: revText, newText: null));
      }
    }

    // Walk current blocks: find blocks that were added (not in revision).
    for (final block in currentBlocks) {
      if (!matched.contains(block.id)) {
        result.add(_DiffLine(
            type: _DiffType.added, oldText: null, newText: block.displayText));
      }
    }

    return result;
  }

}

enum _DiffType { added, removed, changed }

class _DiffLine {
  final _DiffType type;
  final String? oldText;
  final String? newText;

  const _DiffLine({
    required this.type,
    this.oldText,
    this.newText,
  });
}

class _DiffRow extends StatelessWidget {
  final _DiffLine diff;

  const _DiffRow({required this.diff});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Old (revision) side
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _oldBgColor(),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _oldBorderColor(), width: 0.5),
              ),
              child: Text(
                diff.oldText ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: diff.oldText != null
                      ? null
                      : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  decoration: diff.type == _DiffType.removed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // New (current) side
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _newBgColor(),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _newBorderColor(), width: 0.5),
              ),
              child: Text(
                diff.newText ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: diff.newText != null
                      ? null
                      : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _oldBgColor() => switch (diff.type) {
        _DiffType.removed => Colors.red.shade50,
        _DiffType.changed => Colors.amber.shade50,
        _DiffType.added => Colors.transparent,
      };

  Color _oldBorderColor() => switch (diff.type) {
        _DiffType.removed => Colors.red.shade200,
        _DiffType.changed => Colors.amber.shade200,
        _DiffType.added => Colors.grey.shade200,
      };

  Color _newBgColor() => switch (diff.type) {
        _DiffType.added => Colors.green.shade50,
        _DiffType.changed => Colors.green.shade50,
        _DiffType.removed => Colors.transparent,
      };

  Color _newBorderColor() => switch (diff.type) {
        _DiffType.added => Colors.green.shade200,
        _DiffType.changed => Colors.green.shade200,
        _DiffType.removed => Colors.grey.shade200,
      };
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final String label;

  const _LegendChip({
    required this.color,
    required this.borderColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: borderColor, width: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
