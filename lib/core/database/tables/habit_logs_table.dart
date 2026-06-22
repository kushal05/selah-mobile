import 'package:drift/drift.dart';

/// Sync-enabled table for daily habit check-ins.
///
/// Tracks 3 habit types: bible, meditation, journal.
/// One active row per (user, habitType, day) — enforced by a partial unique index
/// on (user_id, habit_type, date_day) WHERE deleted = 0 (created in sync_database.dart).
class HabitLogs extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  // 'bible' | 'meditation' | 'journal'
  TextColumn get habitType => text()();
  // Start-of-day in ms (UTC midnight) — used for streak calculation
  IntColumn get dateDay => integer()();
  IntColumn get createdAt => integer()();

  // Sync fields (added in schema v30)
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();
  IntColumn get trashedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
