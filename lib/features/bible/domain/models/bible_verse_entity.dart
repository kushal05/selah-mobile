import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Domain entity representing a row in the bible_verses table.
///
/// Maps directly to the SQLite schema:
///   id INTEGER PRIMARY KEY AUTOINCREMENT
///   translation TEXT NOT NULL
///   book_id INTEGER NOT NULL
///   chapter INTEGER NOT NULL
///   verse INTEGER NOT NULL
///   text TEXT NOT NULL
///   UNIQUE(translation, book_id, chapter, verse)
@immutable
class BibleVerseEntity extends Equatable {
  final int id;
  final String translation;
  final int bookId;
  final int chapter;
  final int verse;
  final String text;

  const BibleVerseEntity({
    required this.id,
    required this.translation,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  factory BibleVerseEntity.fromRow(Map<String, dynamic> row) {
    return BibleVerseEntity(
      id: row['id'] as int,
      translation: row['translation'] as String,
      bookId: row['book_id'] as int,
      chapter: row['chapter'] as int,
      verse: row['verse'] as int,
      text: row['text'] as String,
    );
  }

  @override
  List<Object?> get props => [id, translation, bookId, chapter, verse, text];

  @override
  String toString() => 'BibleVerseEntity($translation $bookId:$chapter:$verse)';
}
