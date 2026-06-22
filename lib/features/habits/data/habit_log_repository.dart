import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/sync_database.dart';
import '../../../core/sync/models/habit_log_model.dart';
import '../../../core/sync/models/oplog_entry.dart';
import '../../../core/sync/repositories/base_sync_repository.dart';

/// The three trackable daily habits.
enum HabitType {
  bible('bible', 'Bible Reading'),
  meditation('meditation', 'Meditation');

  final String key;
  final String label;
  const HabitType(this.key, this.label);

  static HabitType fromKey(String key) =>
      HabitType.values.firstWhere((h) => h.key == key,
          orElse: () => HabitType.bible);
}

const msPerDay = 86400000;

/// Returns the UTC midnight timestamp (ms) for a given [date].
int toDateDay(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day).millisecondsSinceEpoch;
}

/// Sync-aware repository for daily habit check-ins.
///
/// Every write creates an oplog entry in the same transaction so that
/// the sync engine can replicate changes to other devices.
class HabitLogRepository extends BaseSyncRepository<HabitLogModel> {
  final SyncDatabase _db;
  final String _userId;
  final String _deviceId;

  HabitLogRepository(this._db, this._userId, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.habitLog;

  static const _table = 'habit_logs';

  // ── READ ────────────────────────────────────────────────────────────────────

  /// Watch which habits have been completed today (set of [HabitType.key]).
  ///
  /// Fetches all rows for the user and filters to today in Dart so that
  /// [toDateDay] is re-evaluated on every emission — correctly handles the
  /// app staying open past midnight without requiring a stream restart.
  Stream<Set<String>> watchTodayCompletedKeys() {
    return _db
        .customSelect(
          'SELECT habit_type, date_day FROM $_table '
          'WHERE user_id = ? AND deleted = 0',
          variables: [Variable.withString(_userId)],
          readsFrom: {_db.habitLogs},
        )
        .watch()
        .map((rows) {
          final today = toDateDay(DateTime.now());
          return rows
              .where((r) => r.read<int>('date_day') == today)
              .map((r) => r.read<String>('habit_type'))
              .toSet();
        });
  }

  /// Current streak (consecutive days) for a given habit type.
  ///
  /// Counts backwards from today (or yesterday if today isn't done yet).
  Future<int> getStreak(HabitType habit) async {
    final today = toDateDay(DateTime.now());

    final rows = await _db.customSelect(
      'SELECT date_day FROM $_table '
      'WHERE user_id = ? AND habit_type = ? AND deleted = 0 '
      'ORDER BY date_day DESC',
      variables: [
        Variable.withString(_userId),
        Variable.withString(habit.key),
      ],
    ).get();

    if (rows.isEmpty) return 0;

    final days = rows.map((r) => r.read<int>('date_day')).toList();
    int expected = days.first == today ? today : today - msPerDay;
    if (days.first != expected) return 0;

    int streak = 0;
    for (final day in days) {
      if (day == expected) {
        streak++;
        expected -= msPerDay;
      } else {
        break;
      }
    }
    return streak;
  }

  /// Best (all-time longest) streak for a given habit type.
  Future<int> getBestStreak(HabitType habit) async {

    final rows = await _db.customSelect(
      'SELECT date_day FROM $_table '
      'WHERE user_id = ? AND habit_type = ? AND deleted = 0 '
      'ORDER BY date_day ASC',
      variables: [
        Variable.withString(_userId),
        Variable.withString(habit.key),
      ],
    ).get();

    if (rows.isEmpty) return 0;

    final days = rows.map((r) => r.read<int>('date_day')).toList();
    int best = 1;
    int current = 1;

    for (int i = 1; i < days.length; i++) {
      if (days[i] - days[i - 1] == msPerDay) {
        current++;
        if (current > best) best = current;
      } else {
        current = 1;
      }
    }
    return best;
  }

  /// Completion history for the past [months] months.
  /// Returns a Set of [dateDay] values (UTC midnight ms) where the habit was done.
  Future<Set<int>> getHistory(HabitType habit, {int months = 3}) async {
    final cutoff = DateTime.now().subtract(Duration(days: months * 31));
    final cutoffMs = toDateDay(cutoff);

    final rows = await _db.customSelect(
      'SELECT date_day FROM $_table '
      'WHERE user_id = ? AND habit_type = ? AND deleted = 0 AND date_day >= ? '
      'ORDER BY date_day DESC',
      variables: [
        Variable.withString(_userId),
        Variable.withString(habit.key),
        Variable.withInt(cutoffMs),
      ],
    ).get();

    return rows.map((r) => r.read<int>('date_day')).toSet();
  }

  /// Weekly stats: returns a 7-element list (Monday → Sunday) of booleans
  /// indicating whether the habit was completed on each day of the current week.
  Future<List<bool>> getWeeklyStats(HabitType habit) async {
    final now = DateTime.now();
    // Find Monday of this week
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekDays = List.generate(7, (i) {
      return toDateDay(monday.add(Duration(days: i)));
    });

    final rows = await _db.customSelect(
      'SELECT date_day FROM $_table '
      'WHERE user_id = ? AND habit_type = ? AND deleted = 0 '
      'AND date_day >= ? AND date_day <= ?',
      variables: [
        Variable.withString(_userId),
        Variable.withString(habit.key),
        Variable.withInt(weekDays.first),
        Variable.withInt(weekDays.last),
      ],
    ).get();

    final completed = rows.map((r) => r.read<int>('date_day')).toSet();
    return weekDays.map((d) => completed.contains(d)).toList();
  }

  // ── WRITE ───────────────────────────────────────────────────────────────────

  /// Toggle today's check-in for [habit].
  ///
  /// - If not yet checked in: inserts a new row + INSERT oplog entry.
  /// - If already checked in: soft-deletes the row + DELETE oplog entry.
  ///
  /// Returns true if now checked in, false if unchecked.
  Future<bool> toggleToday(HabitType habit) async {
    final today = toDateDay(DateTime.now());

    final existing = await _db.customSelect(
      'SELECT id, version, created_at, updated_at, deleted, trashed_at '
      'FROM $_table '
      'WHERE user_id = ? AND habit_type = ? AND date_day = ? AND deleted = 0',
      variables: [
        Variable.withString(_userId),
        Variable.withString(habit.key),
        Variable.withInt(today),
      ],
    ).getSingleOrNull();

    if (existing != null) {
      // Uncheck: soft delete
      final model = HabitLogModel(
        id: existing.data['id'] as String,
        userId: _userId,
        habitType: habit.key,
        dateDay: today,
        createdAt: existing.data['created_at'] as int,
        updatedAt: existing.data['updated_at'] as int,
        version: existing.data['version'] as int,
        deleted: 0,
        trashedAt: existing.data['trashed_at'] as int?,
      ).softDelete();

      final oplogEntry = createDeleteOp(model);

      await _db.transaction(() async {
        await (_db.update(_db.habitLogs)
              ..where((t) => t.id.equals(model.id)))
            .write(HabitLogsCompanion(
          deleted: const Value(1),
          version: Value(model.version),
          updatedAt: Value(model.updatedAt),
        ));
        await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
      });
      return false;
    }

    // Check in: insert new row
    final model = HabitLogModel.create(
      id: const Uuid().v4(),
      userId: _userId,
      habitType: habit.key,
      dateDay: today,
    );

    final oplogEntry = createInsertOp(model);

    await _db.transaction(() async {
      await _db.into(_db.habitLogs).insertOnConflictUpdate(HabitLogsCompanion(
        id: Value(model.id),
        userId: Value(_userId),
        habitType: Value(habit.key),
        dateDay: Value(today),
        createdAt: Value(model.createdAt),
        updatedAt: Value(model.updatedAt),
        version: const Value(1),
        deleted: const Value(0),
      ));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
    return true;
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────────

  OplogCompanion _oplogToCompanion(OplogEntry entry) {
    return OplogCompanion(
      opId: Value(entry.opId),
      entityType: Value(entry.entityType.toDbValue()),
      entityId: Value(entry.entityId),
      operation: Value(entry.operation.toDbValue()),
      payloadJson: Value(entry.payloadJson),
      timestamp: Value(entry.timestamp),
      deviceId: Value(entry.deviceId),
      synced: Value(entry.synced ? 1 : 0),
      entityVersion: Value(entry.entityVersion),
      serverTimestamp: Value(entry.serverTimestamp),
    );
  }
}
