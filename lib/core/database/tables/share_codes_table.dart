import 'package:drift/drift.dart';

/// Local-only lookup table mapping share codes to entity_access records.
///
/// When migrating from SharedPrayers (which had a shareCode field) to
/// entity_access (which is generic and has no shareCode), this table
/// preserves the code → entity mapping.
///
/// Not synced via oplog. Share codes are resolved server-side.
class ShareCodes extends Table {
  /// The share code string (e.g., 12-char alphanumeric)
  TextColumn get code => text()();

  /// FK to entity_access.id
  TextColumn get entityAccessId => text()();

  /// Entity type: prayer, note, song, etc.
  TextColumn get entityType => text()();

  /// The shared entity's ID
  TextColumn get entityId => text()();

  @override
  Set<Column> get primaryKey => {code};
}
