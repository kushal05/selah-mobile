import 'package:drift/drift.dart';

/// Preachers table schema
/// Stores preacher/speaker information
class Preachers extends Table {
  /// Primary key - UUID
  TextColumn get id => text()();

  /// Preacher name
  TextColumn get name => text()();

  /// Creation timestamp
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name}
      ];
}
