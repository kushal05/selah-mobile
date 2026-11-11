import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/sync/models/sync_entity.dart';

/// A note the user wrote on a Bible verse (see the BibleVerseNotes table for
/// how it differs from a highlight's note and from a normal note).
@immutable
class BibleVerseNoteEntity extends Equatable implements SyncEntity {
  @override
  final String id;
  final String userId;
  final int bookId;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final String content;
  @override
  final int version;
  final int createdAt;
  @override
  final int updatedAt;

  /// Set only on the copy a DELETE operation is built from, so its payload
  /// says `deleted: 1`.
  final bool deleted;

  const BibleVerseNoteEntity({
    required this.id,
    this.userId = '',
    required this.bookId,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    required this.content,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  @override
  bool get isDeleted => deleted;

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
        'content': content,
        'version': version,
        'deleted': deleted ? 1 : 0,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// This note with new text: version bumped, updatedAt now.
  BibleVerseNoteEntity copyWithUpdate({required String content}) {
    return BibleVerseNoteEntity(
      id: id,
      userId: userId,
      bookId: bookId,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
      content: content,
      version: version + 1,
      createdAt: createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// The copy a DELETE operation is built from: version bumped, flagged deleted.
  BibleVerseNoteEntity asDeleted() {
    return BibleVerseNoteEntity(
      id: id,
      userId: userId,
      bookId: bookId,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
      content: content,
      version: version + 1,
      createdAt: createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      deleted: true,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        bookId,
        chapter,
        verseStart,
        verseEnd,
        content,
        version,
        createdAt,
        updatedAt,
        deleted,
      ];
}
