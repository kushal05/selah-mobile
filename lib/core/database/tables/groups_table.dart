import 'package:drift/drift.dart';

export '../../domain/enums/group_enums.dart';

/// Groups table for church community groups
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get groupType => text().withDefault(const Constant('church'))();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get joinCode => text().withDefault(const Constant(''))();
  TextColumn get joinPolicy => text().withDefault(const Constant('codeOnly'))();
  TextColumn get createdByUserId => text()();
  TextColumn get userId => text()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  /// Per-field update timestamps for field-level merge conflict resolution.
  /// JSON map of {fieldName: timestampMs}. Empty map '{}' for legacy entities.
  TextColumn get fieldUpdatedAt => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}
