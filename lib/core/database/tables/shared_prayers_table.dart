import 'package:drift/drift.dart';

/// Shared prayer metadata table
/// Tracks which prayers are shared and their sharing permissions
class SharedPrayers extends Table {
  TextColumn get id => text()();
  TextColumn get prayerId => text()();
  TextColumn get sharedByUserId => text()();
  TextColumn get shareCode => text().withDefault(const Constant(''))();
  IntColumn get allowEditing => integer().withDefault(const Constant(0))();
  IntColumn get allowLogging => integer().withDefault(const Constant(1))();
  IntColumn get allowUpdates => integer().withDefault(const Constant(1))();
  TextColumn get userId => text()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
