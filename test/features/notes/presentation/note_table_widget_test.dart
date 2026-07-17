import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/domain/models/note_table.dart';
import 'package:notify/features/notes/presentation/widgets/editor/note_table_widget.dart';

void main() {
  Future<void> pump(WidgetTester tester, NoteTable table,
      {VoidCallback? onRemove}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteTableWidget(table: table, onRemove: onRemove),
      ),
    ));
  }

  NoteTable tableOf(List<List<String>> rows, [List<TableColumnAlign>? aligns]) =>
      NoteTable(
        rows: rows
            .map((r) => r.map((c) => NoteTableCell(text: c)).toList())
            .toList(),
        alignments: aligns ?? const [],
      );

  testWidgets('renders header and body cells', (tester) async {
    await pump(tester, tableOf([
      ['Name', 'Qty'],
      ['Apples', '3'],
    ]));
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Qty'), findsOneWidget);
    expect(find.text('Apples'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('ragged rows render without throwing', (tester) async {
    await pump(tester, tableOf([
      ['a', 'b', 'c'],
      ['1'], // short row
    ]));
    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('empty table renders nothing rather than asserting',
      (tester) async {
    await pump(tester, NoteTable.empty);
    expect(tester.takeException(), isNull);
    expect(find.byType(Table), findsNothing);
  });

  testWidgets('zero-column table (corrupt data) does not crash',
      (tester) async {
    // rows present but every row empty -> columnCount == 0, which would
    // otherwise assert inside Table.
    await pump(tester, const NoteTable(rows: [[]], alignments: []));
    expect(tester.takeException(), isNull);
    expect(find.byType(Table), findsNothing);
  });

  testWidgets('remove button shown only in the editor', (tester) async {
    await pump(tester, tableOf([['a']]));
    expect(find.byIcon(Icons.close), findsNothing);

    var removed = false;
    await pump(tester, tableOf([['a']]), onRemove: () => removed = true);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    expect(removed, true);
  });
}
