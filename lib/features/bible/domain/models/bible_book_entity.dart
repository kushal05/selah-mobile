import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Domain entity representing a row in the bible_books table.
///
/// Maps directly to the SQLite schema:
///   id INTEGER PRIMARY KEY (1..66)
///   name TEXT            — full canonical name
///   short_name TEXT      — standard abbreviation
///   testament INTEGER    — 0 = OT, 1 = NT
///   sort_order INTEGER   — canonical ordering (1..66)
@immutable
class BibleBookEntity extends Equatable {
  final int id;
  final String name;
  final String shortName;

  /// 0 = Old Testament, 1 = New Testament
  final int testament;
  final int sortOrder;

  const BibleBookEntity({
    required this.id,
    required this.name,
    required this.shortName,
    required this.testament,
    required this.sortOrder,
  });

  bool get isOldTestament => testament == 0;
  bool get isNewTestament => testament == 1;

  factory BibleBookEntity.fromRow(Map<String, dynamic> row) {
    return BibleBookEntity(
      id: row['id'] as int,
      name: row['name'] as String,
      shortName: row['short_name'] as String,
      testament: row['testament'] as int,
      sortOrder: row['sort_order'] as int,
    );
  }

  @override
  List<Object?> get props => [id, name, shortName, testament, sortOrder];

  @override
  String toString() => 'BibleBookEntity($id, $name)';
}
