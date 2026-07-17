import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'text_span_format.dart';

/// Horizontal alignment of a table column (from a GFM delimiter row).
enum TableColumnAlign {
  left,
  center,
  right;

  static TableColumnAlign fromName(String value) => TableColumnAlign.values
      .firstWhere((a) => a.name == value, orElse: () => TableColumnAlign.left);
}

/// A single table cell: plain text plus the same offset-based inline formats
/// used everywhere else in the editor, so cells render through
/// `buildFormattedTextSpan` like any other block.
@immutable
class NoteTableCell extends Equatable {
  final String text;
  final List<TextSpanFormat> formats;

  const NoteTableCell({this.text = '', this.formats = const []});

  Map<String, dynamic> toJson() => {
        'text': text,
        if (formats.isNotEmpty)
          'formats': formats.map((f) => f.toJson()).toList(),
      };

  factory NoteTableCell.fromJson(Map<String, dynamic> json) => NoteTableCell(
        text: json['text'] as String? ?? '',
        formats: (json['formats'] as List<dynamic>?)
                ?.map((f) => TextSpanFormat.fromJson(f as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  List<Object?> get props => [text, formats];
}

/// A GFM-style table stored as the JSON `content` of a [BlockType.table] block.
///
/// Mirrors the existing `bibleReference` precedent: structured, non-editable
/// block data is JSON-encoded into the block's single-line `content` string, so
/// no schema/sync change is needed (the sync layer treats content as opaque).
@immutable
class NoteTable extends Equatable {
  /// First row is the header; remaining rows are the body.
  final List<List<NoteTableCell>> rows;

  /// Per-column alignment. Length matches the header's column count.
  final List<TableColumnAlign> alignments;

  const NoteTable({required this.rows, required this.alignments});

  static const empty = NoteTable(rows: [], alignments: []);

  bool get isEmpty => rows.isEmpty;

  /// Number of columns, driven by the widest row so a ragged table still
  /// renders every cell.
  int get columnCount =>
      rows.fold(0, (max, row) => row.length > max ? row.length : max);

  List<NoteTableCell> get header => rows.isEmpty ? const [] : rows.first;

  List<List<NoteTableCell>> get body =>
      rows.length <= 1 ? const [] : rows.sublist(1);

  TableColumnAlign alignAt(int column) => column < alignments.length
      ? alignments[column]
      : TableColumnAlign.left;

  /// Plain text of every cell, for previews and search.
  String get plainText =>
      rows.map((r) => r.map((c) => c.text).join(' ')).join(' ').trim();

  Map<String, dynamic> toJson() => {
        'rows': rows
            .map((row) => row.map((cell) => cell.toJson()).toList())
            .toList(),
        'alignments': alignments.map((a) => a.name).toList(),
      };

  factory NoteTable.fromJson(Map<String, dynamic> json) {
    final rawRows = json['rows'] as List<dynamic>? ?? const [];
    return NoteTable(
      rows: rawRows
          .map((row) => (row as List<dynamic>)
              .map((c) => NoteTableCell.fromJson(c as Map<String, dynamic>))
              .toList())
          .toList(),
      alignments: (json['alignments'] as List<dynamic>? ?? const [])
          .map((a) => TableColumnAlign.fromName(a as String))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [rows, alignments];
}
