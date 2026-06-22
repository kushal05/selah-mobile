import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../sync/models/note_block_model.dart';
import '../sync/models/prayer_model.dart';
import '../sync/repositories/note_repository.dart';
import '../sync/repositories/note_block_repository.dart';
import '../sync/repositories/prayer_repository.dart';

/// Service for exporting data as PDF
class PdfExportService {
  final NoteRepository _noteRepo;
  final NoteBlockRepository _noteBlockRepo;
  final PrayerRepository _prayerRepo;
  final String _userId;

  PdfExportService({
    required NoteRepository noteRepo,
    required NoteBlockRepository noteBlockRepo,
    required PrayerRepository prayerRepo,
    required String userId,
  })  : _noteRepo = noteRepo,
        _noteBlockRepo = noteBlockRepo,
        _prayerRepo = prayerRepo,
        _userId = userId;

  /// Export a single note to PDF
  Future<void> exportNoteToPdf(String noteId) async {
    try {
      final note = await _noteRepo.getNoteById(noteId);
      if (note == null) return;

      final blocks = await _noteBlockRepo.getBlocksForNote(noteId);

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                note.title,
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              _formatDate(note.createdAt),
              style: const pw.TextStyle(
                fontSize: 12,
                color: PdfColors.grey600,
              ),
            ),
            pw.SizedBox(height: 16),
            ...blocks.map(_blockToWidget),
          ],
        ),
      );

      await _saveAndShare(pdf, 'note_${note.title}');
    } catch (e, stackTrace) {
      debugPrint('PdfExportService.exportNoteToPdf failed: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Export active prayers to PDF
  Future<void> exportPrayersToPdf() async {
    try {
      final prayers = await _prayerRepo.getActivePrayers(_userId);

      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Prayer List',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Exported on ${_formatDate(DateTime.now().millisecondsSinceEpoch)}',
              style: const pw.TextStyle(
                fontSize: 12,
                color: PdfColors.grey600,
              ),
            ),
            pw.SizedBox(height: 16),
            ...prayers.map(_prayerToWidget),
          ],
        ),
      );

      await _saveAndShare(pdf, 'prayers');
    } catch (e, stackTrace) {
      debugPrint('PdfExportService.exportPrayersToPdf failed: $e\n$stackTrace');
      rethrow;
    }
  }

  pw.Widget _blockToWidget(NoteBlockModel block) {
    final text = block.plainText;
    if (text.isEmpty && block.blockType != BlockType.divider) {
      return pw.SizedBox(height: 8);
    }

    return switch (block.blockType) {
      BlockType.heading1 => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
          child: pw.Text(text,
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
        ),
      BlockType.heading2 => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(text,
              style: pw.TextStyle(
                  fontSize: 17, fontWeight: pw.FontWeight.bold)),
        ),
      BlockType.heading3 => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
          child: pw.Text(text,
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold)),
        ),
      BlockType.bulletList => pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('\u2022  '),
              pw.Expanded(child: pw.Text(text)),
            ],
          ),
        ),
      BlockType.numberedList => pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('${block.orderIndex + 1}.  '),
              pw.Expanded(child: pw.Text(text)),
            ],
          ),
        ),
      BlockType.checkbox => pw.Padding(
          padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(block.isChecked ? '[x]  ' : '[ ]  '),
              pw.Expanded(child: pw.Text(text)),
            ],
          ),
        ),
      BlockType.quote => pw.Container(
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.only(left: 16, bottom: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: PdfColors.grey400, width: 3),
            ),
          ),
          child: pw.Text(text,
              style: const pw.TextStyle(color: PdfColors.grey700)),
        ),
      BlockType.code => pw.Container(
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.only(bottom: 4),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(text,
              style: pw.TextStyle(
                  font: pw.Font.courier(), fontSize: 11)),
        ),
      BlockType.divider => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(),
        ),
      _ => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(text),
        ),
    };
  }

  pw.Widget _prayerToWidget(PrayerModel prayer) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            prayer.title,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (prayer.content.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(prayer.content, style: const pw.TextStyle(fontSize: 12)),
          ],
          pw.SizedBox(height: 4),
          pw.Text(
            '${prayer.frequency.name} | ${prayer.status.name}',
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveAndShare(pw.Document pdf, String name) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${name}_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Selah Export - $name',
    );
  }
}
