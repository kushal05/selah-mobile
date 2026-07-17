import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:notify/core/services/pdf_export_service.dart';
import 'package:notify/core/sync/models/note_block_model.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/notes/domain/models/note_table.dart';

/// `bibleReference` and `table` blocks keep structured JSON in their content.
/// Rendering that content as text printed a wall of braces into exported PDFs.
/// These tests render real PDF bytes and assert the payload never leaks.
void main() {
  /// Render blocks to real PDF bytes and return them as text.
  ///
  /// Compression is off and a standard-14 font is forced so glyphs are written
  /// as string literals rather than an embedded subset — that makes the page's
  /// actual text greppable, so these assertions genuinely fail if raw JSON is
  /// ever rendered.
  Future<String> renderToText(List<NoteBlockModel> blocks) async {
    final doc = pw.Document(
      compress: false,
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
        italic: pw.Font.helveticaOblique(),
        boldItalic: pw.Font.helveticaBoldOblique(),
      ),
    );
    doc.addPage(
      pw.Page(
        build: (_) => pw.Column(
          children: blocks.map(PdfExportService.blockToWidget).toList(),
        ),
      ),
    );
    return latin1.decode(await doc.save(), allowInvalid: true);
  }

  NoteBlockModel block(BlockType type, Map<String, dynamic> content) =>
      NoteBlockModel.create(
        id: 'b1',
        noteId: 'n1',
        blockType: type,
        content: content,
        orderIndex: 0,
      );

  group('PDF export — bible reference', () {
    // Built from the real model so the fixture matches production's payload.
    final refJson = jsonEncode(BibleReference(
      reference: const BibleVerseReference(
        book: 'John',
        chapter: 3,
        verses: [16],
        version: 'ESV',
      ),
      text: const [
        BibleVerseText(verse: 16, content: 'ForGodSoLovedTheWorld'),
      ],
      source: 'local',
      insertedAt: 1784196741600,
      display: const BibleVerseDisplay(),
      pending: false,
    ).toJson());

    test('renders the reference, not raw JSON', () async {
      final out = await renderToText(
          [block(BlockType.bibleReference, {'text': refJson})]);

      expect(out, contains('John'));
      expect(out, contains('ForGodSoLovedTheWorld'));
      // None of the JSON payload may reach the page.
      expect(out, isNot(contains('insertedAt')));
      expect(out, isNot(contains('showVerseNumbers')));
      expect(out, isNot(contains('"reference"')));
    });

    test('malformed reference degrades to a placeholder', () async {
      final out = await renderToText(
          [block(BlockType.bibleReference, {'text': 'not json'})]);
      // Text is emitted word-by-word during layout, so assert on a word.
      expect(out, contains('Bible'));
    });
  });

  group('PDF export — table', () {
    final table = NoteTable(
      rows: [
        [const NoteTableCell(text: 'Name'), const NoteTableCell(text: 'Qty')],
        [const NoteTableCell(text: 'Apples'), const NoteTableCell(text: '3')],
      ],
      alignments: const [TableColumnAlign.left, TableColumnAlign.right],
    );

    test('renders cells as a table, not raw JSON', () async {
      final out = await renderToText([
        block(BlockType.table, {
          'text': table.plainText,
          'table': table.toJson(),
        }),
      ]);

      expect(out, contains('Name'));
      expect(out, contains('Apples'));
      expect(out, isNot(contains('"rows"')));
      expect(out, isNot(contains('alignments')));
    });

    test('falls back to plain text when the structure is missing', () async {
      final out = await renderToText([
        block(BlockType.table, {'text': 'Name Qty Apples 3'}),
      ]);
      expect(out, contains('Apples'));
    });
  });

  test('ordinary blocks still render', () async {
    final out = await renderToText([
      block(BlockType.heading1, {'text': 'My Heading'}),
      block(BlockType.bulletList, {'text': 'a bullet'}),
    ]);
    // Layout emits each word separately, so assert on single words.
    expect(out, contains('Heading'));
    expect(out, contains('bullet'));
  });
}
