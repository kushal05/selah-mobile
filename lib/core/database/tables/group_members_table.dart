import 'package:drift/drift.dart';

export '../../domain/enums/group_enums.dart';

/// Group members table
class GroupMembers extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get memberUserId => text()();
  TextColumn get memberUsername => text().withDefault(const Constant(''))();
  TextColumn get memberDisplayName => text().withDefault(const Constant(''))();
  TextColumn get role => text().withDefault(const Constant('member'))();
  TextColumn get userId => text()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
