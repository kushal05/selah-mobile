import 'package:flutter/material.dart';

import '../../../domain/models/note_table.dart';
import 'formatted_text_span.dart';

/// Renders a [NoteTable] as a bordered, horizontally scrollable table.
///
/// Shared by the editor (non-editable card, like the Bible reference block) and
/// the read-only note view so both look identical. Tables are created by
/// pasting Markdown; cell contents are not editable in place.
class NoteTableWidget extends StatelessWidget {
  final NoteTable table;

  /// Shown as a small delete affordance in the editor; null in read-only.
  final VoidCallback? onRemove;

  /// Called when a link inside a cell is tapped (read-only only).
  final ValueChanged<String>? onLinkTap;

  const NoteTableWidget({
    super.key,
    required this.table,
    this.onRemove,
    this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = table.columnCount;
    // A Table with zero columns asserts, and corrupted JSON could yield rows
    // that are all empty — render nothing rather than crash the note.
    if (table.isEmpty || columns == 0) return const SizedBox.shrink();

    final borderColor = theme.colorScheme.onSurface.withValues(alpha: 0.2);

    final content = Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      // Wide tables must scroll inside their own box rather than overflow.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.symmetric(
            inside: BorderSide(color: borderColor),
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.05),
              ),
              children: List.generate(
                columns,
                (i) => _cell(context, table.header, i, isHeader: true),
              ),
            ),
            for (final row in table.body)
              TableRow(
                children:
                    List.generate(columns, (i) => _cell(context, row, i)),
              ),
          ],
        ),
      ),
    );

    if (onRemove == null) return content;

    return Stack(
      children: [
        Padding(padding: const EdgeInsets.only(top: 8), child: content),
        Positioned(
          top: 0,
          right: 0,
          child: IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove table',
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    List<NoteTableCell> row,
    int column, {
    bool isHeader = false,
  }) {
    final theme = Theme.of(context);
    // Ragged rows: render an empty cell rather than throwing.
    final cell = column < row.length ? row[column] : const NoteTableCell();

    final style = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontWeight: isHeader ? FontWeight.bold : null,
    );

    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Align(
          alignment: switch (table.alignAt(column)) {
            TableColumnAlign.left => Alignment.centerLeft,
            TableColumnAlign.center => Alignment.center,
            TableColumnAlign.right => Alignment.centerRight,
          },
          child: FormattedText(
            text: cell.text,
            formats: cell.formats,
            style: style,
            onLinkTap: onLinkTap,
          ),
        ),
      ),
    );
  }
}
