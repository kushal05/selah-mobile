import 'package:drift/drift.dart';

export '../../domain/enums/prayer_enums.dart';

/// Prayer collaborators table
/// Tracks who has access to a shared prayer and their role
class PrayerCollaborators extends Table {
  TextColumn get id => text()();
  TextColumn get prayerId => text()();
  TextColumn get sharedPrayerId => text()();
  TextColumn get collaboratorUserId => text()();
  TextColumn get collaboratorUsername =>
      text().withDefault(const Constant(''))();
  TextColumn get role => text().withDefault(const Constant('viewer'))();
  TextColumn get addedByUserId => text()();
  TextColumn get userId => text()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
