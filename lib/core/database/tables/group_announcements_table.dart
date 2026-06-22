import 'package:drift/drift.dart';

/// Group announcements table
class GroupAnnouncements extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get title => text()();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get authorUserId => text()();
  TextColumn get authorUsername => text().withDefault(const Constant(''))();
  IntColumn get pinned => integer().withDefault(const Constant(0))();
  TextColumn get userId => text()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
