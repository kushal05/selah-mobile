import 'package:drift/drift.dart';

/// Remote operations whose apply keeps failing for a reason a retry might fix.
///
/// The pull loop cannot simply skip a failed operation: skipping advances the
/// cursor past it and the server never sends it again, so a transient failure
/// like a full disk would discard the user's data permanently. It therefore
/// leaves the cursor alone and retries the page on the next sync.
///
/// That alone would wedge sync forever on an operation that can never apply
/// but does not throw one of the recognised parse errors. This table is the
/// bound on that: each failure increments [attempts], and once an operation
/// has failed enough times the pull skips it and moves on, recording why so it
/// can be surfaced rather than lost silently.
@DataClassName('FailedRemoteOp')
class FailedRemoteOps extends Table {
  /// The oplog operation id from the server.
  TextColumn get opId => text()();

  /// Entity this operation targeted, for reporting.
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// How many pulls have tried and failed to apply it.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// The most recent error, truncated — for the sync status screen and logs.
  TextColumn get lastError => text().withDefault(const Constant(''))();

  /// When it last failed, ms since epoch.
  IntColumn get lastAttemptAt => integer().withDefault(const Constant(0))();

  /// Set once [attempts] passes the limit and the pull started skipping it.
  /// Kept rather than deleted so it can be reported and retried deliberately.
  BoolColumn get deadLettered => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {opId};
}
