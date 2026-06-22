import 'package:drift/drift.dart';

import '../../../../core/database/sync_database.dart';
import '../../domain/models/weekly_digest.dart';

/// Aggregates the last N days of user activity into a [WeeklyDigest]. Pure
/// read-only — no writes, no oplog entries.
///
/// All queries filter `deleted = 0` and the user's `userId` to stay within
/// the sync-correctness invariants spelled out in CLAUDE.md.
class WeeklyDigestService {
  final SyncDatabase _db;
  WeeklyDigestService(this._db);

  /// Compute a digest covering the last [days] days for [userId].
  /// Default window is 7 days.
  Future<WeeklyDigest> compute({required String userId, int days = 7}) async {
    final now = DateTime.now();
    final windowStart = now.subtract(Duration(days: days));
    final startMs = windowStart.millisecondsSinceEpoch;

    final prayerLogsCount = await _prayerLogsCount(userId, startMs);
    final prayerDays = await _prayerDaysActive(userId, windowStart, now);
    final prayersAnswered = await _prayersAnswered(userId, startMs);
    final notesCreated = await _notesCreated(userId, startMs);
    final notesEdited = await _notesEdited(userId, startMs);
    final (chapters, topChapters) =
        await _chaptersOpened(userId, startMs);
    final peopleMentioned = await _peopleMentioned(userId, startMs);
    final topPrayerTitles = await _topPrayerTitles(userId, startMs);

    return WeeklyDigest(
      windowStart: windowStart,
      windowEnd: now,
      days: days,
      prayersLogged: prayerLogsCount,
      prayerDaysActive: prayerDays,
      prayersAnswered: prayersAnswered,
      notesCreated: notesCreated,
      notesEdited: notesEdited,
      chaptersOpened: chapters,
      peopleMentioned: peopleMentioned,
      topChapters: topChapters,
      topPrayerTitles: topPrayerTitles,
    );
  }

  Future<int> _prayerLogsCount(String userId, int startMs) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM prayer_logs WHERE user_id = ? AND deleted = 0 '
      'AND trashed_at IS NULL AND logged_at >= ?',
      variables: [Variable.withString(userId), Variable.withInt(startMs)],
      readsFrom: {_db.prayerLogs},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> _prayerDaysActive(
    String userId,
    DateTime windowStart,
    DateTime windowEnd,
  ) async {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final row = await _db.customSelect(
      'SELECT COUNT(DISTINCT session_date) AS c FROM prayer_logs '
      'WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL '
      'AND session_date BETWEEN ? AND ?',
      variables: [
        Variable.withString(userId),
        Variable.withString(fmt(windowStart)),
        Variable.withString(fmt(windowEnd)),
      ],
      readsFrom: {_db.prayerLogs},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> _prayersAnswered(String userId, int startMs) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM prayers WHERE user_id = ? AND deleted = 0 '
      'AND answered_at IS NOT NULL AND answered_at >= ?',
      variables: [Variable.withString(userId), Variable.withInt(startMs)],
      readsFrom: {_db.prayers},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> _notesCreated(String userId, int startMs) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM sync_notes WHERE user_id = ? AND deleted = 0 '
      'AND created_at >= ?',
      variables: [Variable.withString(userId), Variable.withInt(startMs)],
      readsFrom: {_db.syncNotes},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<int> _notesEdited(String userId, int startMs) async {
    // "Edited" means updated in window but created before it — so we don't
    // double-count brand-new notes against the edit number.
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM sync_notes WHERE user_id = ? AND deleted = 0 '
      'AND updated_at >= ? AND created_at < ?',
      variables: [
        Variable.withString(userId),
        Variable.withInt(startMs),
        Variable.withInt(startMs),
      ],
      readsFrom: {_db.syncNotes},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<(int, List<String>)> _chaptersOpened(
    String userId,
    int startMs,
  ) async {
    final distinctRow = await _db.customSelect(
      'SELECT COUNT(DISTINCT book || "_" || chapter) AS c '
      'FROM bible_reference_history '
      'WHERE user_id = ? AND deleted = 0 AND opened_at >= ?',
      variables: [Variable.withString(userId), Variable.withInt(startMs)],
      readsFrom: {_db.bibleReferenceHistory},
    ).getSingle();

    final topRows = await _db.customSelect(
      'SELECT book, chapter, COUNT(*) AS opens FROM bible_reference_history '
      'WHERE user_id = ? AND deleted = 0 AND opened_at >= ? '
      'GROUP BY book, chapter ORDER BY opens DESC LIMIT 3',
      variables: [Variable.withString(userId), Variable.withInt(startMs)],
      readsFrom: {_db.bibleReferenceHistory},
    ).get();
    final top = topRows
        .map((r) => '${r.read<String>('book')} ${r.read<int>('chapter')}')
        .toList();
    return (distinctRow.read<int>('c'), top);
  }

  Future<int> _peopleMentioned(String userId, int startMs) async {
    final row = await _db.customSelect(
      'SELECT COUNT(DISTINCT person_id) AS c FROM sync_prayer_people '
      'WHERE user_id = ? AND deleted = 0 AND trashed_at IS NULL '
      'AND created_at >= ?',
      variables: [Variable.withString(userId), Variable.withInt(startMs)],
      readsFrom: {_db.syncPrayerPeople},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<List<String>> _topPrayerTitles(String userId, int startMs) async {
    final rows = await _db.customSelect(
      'SELECT p.title AS title, COUNT(l.id) AS logs FROM prayer_logs l '
      'JOIN prayers p ON p.id = l.prayer_id '
      'WHERE l.user_id = ? AND l.deleted = 0 AND l.trashed_at IS NULL '
      'AND l.logged_at >= ? AND p.deleted = 0 '
      'GROUP BY p.id ORDER BY logs DESC LIMIT 3',
      variables: [Variable.withString(userId), Variable.withInt(startMs)],
      readsFrom: {_db.prayerLogs, _db.prayers},
    ).get();
    return rows.map((r) => r.read<String>('title')).toList();
  }
}
