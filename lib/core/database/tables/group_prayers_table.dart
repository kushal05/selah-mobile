import 'package:drift/drift.dart';

/// Group prayers table
/// Links prayers to groups for shared prayer lists
class GroupPrayers extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get prayerId => text()();
  TextColumn get addedByUserId => text()();
  TextColumn get addedByUsername => text().withDefault(const Constant(''))();
  TextColumn get userId => text()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
