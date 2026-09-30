// A migration step that throws leaves the schema version where it was, so the
// next launch retries the same step — hits the column it already added — and
// the database never opens again. Ten of the sixteen steps that add columns
// guarded against that; six did not.

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  _sourceRule();

  /// Columns the previously unguarded steps add, and the step that adds them.
  const addedColumns = <String, (String table, String column)>{
    'v3':  ('prayers', 'user_id'),
    'v18': ('sync_notes', 'field_updated_at'),
    'v23': ('feedback_threads', 'priority'),
    'v25': ('sync_notes', 'trashed_at'),
    'v30': ('habit_logs', 'updated_at'),
    'v31': ('songs', 'notes'),
  };

  for (final entry in addedColumns.entries) {
    test('adding ${entry.value.$2} twice is a no-op (${entry.key})', () async {
      final db = SyncDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final (table, column) = entry.value;

      Future<String> typeOf() async {
        final cols = await db.customSelect('PRAGMA table_info($table)').get();
        return cols
            .firstWhere((r) => r.read<String>('name') == column)
            .read<String>('type');
      }

      final before = await typeOf();

      // The column is already there — a fresh database has the full schema.
      // Re-running the step's own guarded add must do nothing, not throw.
      await expectLater(
        db.addColumnForTesting(table, column, '$column BLOB'),
        completes,
        reason: 'a re-run of this step would brick the database',
      );

      expect(await typeOf(), before,
          reason: 'the guard let a second, different definition through');
    });
  }

  test('a column that is genuinely missing is still added', () async {
    final db = SyncDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    await db.addColumnForTesting('songs', 'probe_col', 'probe_col TEXT');

    final cols = await db.customSelect('PRAGMA table_info(songs)').get();
    expect(cols.map((r) => r.read<String>('name')), contains('probe_col'),
        reason: 'the guard is skipping columns that are not there');
  });
}

// ─── The source-level rule ────────────────────────────────────────────────────

/// Every `ADD COLUMN` in the migration chain is guarded, and stays guarded.
///
/// Two guard idioms now live in this file: the `_addColumn` helper, and the
/// older inline `PRAGMA table_info` + `if (!names.contains('col'))` blocks. Both
/// are correct, and the inline ones are not worth converting — one of them sits
/// behind an outer check that the table exists at all, which a blanket rewrite
/// of the most unrecoverable file in the app would have to preserve by hand.
///
/// What a mixed convention does cost is the next step someone writes: with two
/// right answers visible, picking neither is easy, and that is exactly how six
/// steps came to have no guard. So the rule is enforced here rather than by
/// making the idiom singular.
void _sourceRule() {
  test('no ADD COLUMN in the migration chain is unguarded', () {
    final lines = File('lib/core/database/sync_database.dart').readAsLinesSync();
    final alter = RegExp(r'ALTER TABLE (\S+) ADD COLUMN (\w+)');
    final violations = <String>[];
    var sawAny = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
      final m = alter.firstMatch(line);
      if (m == null) continue;
      // The helper's own statement, which interpolates its arguments.
      if (m.group(1) == r'$table') continue;
      sawAny = true;

      final column = m.group(2)!;
      // Guarded either by the helper, or by an explicit check naming this same
      // column. Checking the name matches is the point: a guard that tests the
      // wrong column reads as safe and is not.
      final context = lines.sublist((i - 8).clamp(0, i), i + 1).join('\n');
      final guarded = context.contains('_addColumn(') ||
          context.contains(".contains('$column')");
      if (!guarded) {
        violations.add('line ${i + 1}: ${m.group(1)}.$column');
      }
    }

    // Without this the rule passes on a file it failed to read, or on one where
    // the regex stopped matching because the statements were reformatted.
    expect(sawAny, isTrue,
        reason: 'found no ALTER TABLE … ADD COLUMN at all — has the file moved, '
            'or the statements been reformatted past this regex?');
    expect(violations, isEmpty,
        reason: 'wrap these in _addColumn, or in a check naming the column');
  });
}
