import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../core/sync/models/sync_entity.dart';

/// Preset highlight color palette for Bible verses.
enum HighlightColor {
  yellow(Color(0xFFFFF9C4), Color(0xFFF9A825), 'Yellow'),
  green(Color(0xFFC8E6C9), Color(0xFF2E7D32), 'Green'),
  blue(Color(0xFFBBDEFB), Color(0xFF1565C0), 'Blue'),
  pink(Color(0xFFF8BBD0), Color(0xFFC2185B), 'Pink'),
  orange(Color(0xFFFFE0B2), Color(0xFFEF6C00), 'Orange'),
  purple(Color(0xFFE1BEE7), Color(0xFF7B1FA2), 'Purple');

  final Color backgroundColor;
  final Color foregroundColor;
  final String label;

  const HighlightColor(this.backgroundColor, this.foregroundColor, this.label);

  static HighlightColor fromName(String name) {
    return HighlightColor.values.firstWhere(
      (c) => c.name == name,
      orElse: () => HighlightColor.yellow,
    );
  }
}

/// Domain entity representing a Bible verse highlight.
///
/// Implements [SyncEntity] so highlights are written to the oplog and
/// synced across the user's devices. Flutter-only entity type for now
/// (pending Worker support — same pattern as feedbackThread).
@immutable
class BibleHighlightEntity extends Equatable implements SyncEntity {
  @override
  final String id;
  final String userId;
  final int bookId;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final HighlightColor color;
  final String note;
  @override
  final int version;
  final int createdAt;
  @override
  final int updatedAt;

  const BibleHighlightEntity({
    required this.id,
    this.userId = '',
    required this.bookId,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    required this.color,
    this.note = '',
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  // ── SyncEntity ────────────────────────────────────────────────────────────

  @override
  bool get isDeleted => false;

  @override
  int? get trashedAt => null;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'bookId': bookId,
        'chapter': chapter,
        'verseStart': verseStart,
        'verseEnd': verseEnd,
        'color': color.name,
        'note': note,
        'version': version,
        'deleted': 0,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Whether this highlight covers a single verse.
  bool get isSingleVerse => verseStart == verseEnd;

  /// Whether a given verse number falls within this highlight's range.
  bool coversVerse(int verse) => verse >= verseStart && verse <= verseEnd;

  /// Whether this highlight has a user note.
  bool get hasNote => note.isNotEmpty;

  BibleHighlightEntity copyWith({
    String? id,
    String? userId,
    int? bookId,
    int? chapter,
    int? verseStart,
    int? verseEnd,
    HighlightColor? color,
    String? note,
    int? version,
    int? createdAt,
    int? updatedAt,
  }) {
    return BibleHighlightEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      bookId: bookId ?? this.bookId,
      chapter: chapter ?? this.chapter,
      verseStart: verseStart ?? this.verseStart,
      verseEnd: verseEnd ?? this.verseEnd,
      color: color ?? this.color,
      note: note ?? this.note,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns a new entity with bumped version and current updatedAt.
  BibleHighlightEntity copyWithUpdate({
    HighlightColor? color,
    String? note,
  }) {
    return copyWith(
      color: color,
      note: note,
      version: version + 1,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  List<Object?> get props =>
      [id, userId, bookId, chapter, verseStart, verseEnd, color, note, version];
}
