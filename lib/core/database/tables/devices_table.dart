import 'package:drift/drift.dart';

/// Devices table schema
///
/// Per spec section 3.2:
/// Tracks device identity for sync attribution.
///
/// Each device gets a unique ID that:
/// - Is included in every oplog entry
/// - Helps debug sync issues
/// - Enables conflict attribution
/// - Survives app reinstalls (persisted in DB)
class Devices extends Table {
  /// Primary key - device UUID
  TextColumn get id => text()();

  /// Human-readable device name
  /// e.g., "John's iPhone", "Work Laptop"
  TextColumn get name => text()();

  /// Device platform (ios, android, web, macos, windows, linux)
  TextColumn get platform => text()();

  /// App version when device was registered
  TextColumn get appVersion => text()();

  /// Timestamp when device was first registered (Unix milliseconds)
  IntColumn get createdAt => integer()();

  /// Timestamp of last activity from this device (Unix milliseconds)
  IntColumn get lastActiveAt => integer()();

  /// Whether this is the current device (0 or 1)
  /// Only one device should have this set to 1
  IntColumn get isCurrentDevice => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
