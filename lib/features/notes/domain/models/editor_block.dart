import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../bible/domain/models/bible_reference.dart';
import 'block_type.dart';
import 'note_section.dart';
import 'text_span_format.dart';

/// Represents a single block in the editor document
@immutable
class EditorBlock extends Equatable {
  /// Unique stable identifier for this block
  final String id;

  /// Type of block
  final BlockType type;

  /// Text content of the block
  final String content;

  /// Formatting spans applied to the content
  final List<TextSpanFormat> formats;

  /// For checkbox blocks: whether the checkbox is checked
  final bool? isChecked;

  /// Indentation level for list items (0 = top level, max 5)
  final int indentLevel;

  /// Which note section this block belongs to
  final NoteSection section;

  const EditorBlock({
    required this.id,
    required this.type,
    required this.content,
    this.formats = const [],
    this.isChecked,
    this.indentLevel = 0,
    this.section = NoteSection.main,
  });

  /// Create a new empty paragraph block
  factory EditorBlock.paragraph({String? id, NoteSection section = NoteSection.main}) {
    return EditorBlock(
      id: id ?? const Uuid().v4(),
      type: BlockType.paragraph,
      content: '',
      section: section,
    );
  }

  /// Create a new empty heading block
  factory EditorBlock.heading({
    required int level,
    String? id,
  }) {
    assert(level >= 1 && level <= 3, 'Heading level must be 1-3');
    final type = level == 1
        ? BlockType.heading1
        : level == 2
            ? BlockType.heading2
            : BlockType.heading3;

    return EditorBlock(
      id: id ?? const Uuid().v4(),
      type: type,
      content: '',
    );
  }

  /// Create a new bullet list block
  factory EditorBlock.bulletList({String? id, int indentLevel = 0}) {
    return EditorBlock(
      id: id ?? const Uuid().v4(),
      type: BlockType.bulletList,
      content: '',
      indentLevel: indentLevel,
    );
  }

  /// Create a new numbered list block
  factory EditorBlock.numberedList({String? id, int indentLevel = 0}) {
    return EditorBlock(
      id: id ?? const Uuid().v4(),
      type: BlockType.numberedList,
      content: '',
      indentLevel: indentLevel,
    );
  }

  /// Create a new checkbox block
  factory EditorBlock.checkbox({String? id, bool isChecked = false, int indentLevel = 0}) {
    return EditorBlock(
      id: id ?? const Uuid().v4(),
      type: BlockType.checkbox,
      content: '',
      isChecked: isChecked,
      indentLevel: indentLevel,
    );
  }

  /// Create a new Bible reference block
  ///
  /// The [content] field stores the JSON-encoded BibleReference data
  /// in the structured format with nested reference, per-verse text,
  /// source tracking, and display options.
  factory EditorBlock.bibleReference({
    String? id,
    required String book,
    required int chapter,
    required List<int> verses,
    required String version,
    required List<BibleVerseText> verseTexts,
    String source = 'local',
    BibleVerseDisplay display = const BibleVerseDisplay(),
    bool pending = false,
  }) {
    final bibleRef = BibleReference(
      reference: BibleVerseReference(
        book: book,
        chapter: chapter,
        verses: verses,
        version: version,
      ),
      text: verseTexts,
      source: source,
      insertedAt: DateTime.now().millisecondsSinceEpoch,
      display: display,
      pending: pending,
    );
    return EditorBlock(
      id: id ?? const Uuid().v4(),
      type: BlockType.bibleReference,
      content: jsonEncode(bibleRef.toJson()),
    );
  }

  /// Copy with modifications.
  ///
  /// [isChecked] uses a sentinel so an explicit `null` clears the flag (e.g.
  /// when a checkbox becomes a paragraph) while omitting it preserves the
  /// current value.
  EditorBlock copyWith({
    String? id,
    BlockType? type,
    String? content,
    List<TextSpanFormat>? formats,
    Object? isChecked = _sentinel,
    int? indentLevel,
    NoteSection? section,
  }) {
    return EditorBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      formats: formats ?? this.formats,
      isChecked:
          identical(isChecked, _sentinel) ? this.isChecked : isChecked as bool?,
      indentLevel: indentLevel ?? this.indentLevel,
      section: section ?? this.section,
    );
  }

  /// Whether this block is empty (no content)
  bool get isEmpty => content.trim().isEmpty;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'formats': formats.map((f) => f.toJson()).toList(),
      if (isChecked != null) 'isChecked': isChecked,
      if (indentLevel > 0) 'indentLevel': indentLevel,
      if (section != NoteSection.main) 'section': section.name,
    };
  }

  /// Create from JSON
  factory EditorBlock.fromJson(Map<String, dynamic> json) {
    return EditorBlock(
      id: json['id'] as String,
      type: BlockType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => BlockType.paragraph,
      ),
      content: json['content'] as String,
      formats: (json['formats'] as List<dynamic>?)
              ?.map((f) => TextSpanFormat.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      isChecked: json['isChecked'] as bool?,
      indentLevel: json['indentLevel'] as int? ?? 0,
      section: NoteSection.fromDbValue(json['section'] as String? ?? 'main'),
    );
  }

  @override
  List<Object?> get props => [id, type, content, formats, isChecked, indentLevel, section];
}

/// Sentinel for [EditorBlock.copyWith] to distinguish "not passed" from an
/// explicit `null` isChecked.
const Object _sentinel = Object();
