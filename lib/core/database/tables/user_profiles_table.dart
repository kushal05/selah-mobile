import 'package:drift/drift.dart';

/// User profile table with username for the friends/social system
class UserProfiles extends Table {
  /// Primary key - UUID
  TextColumn get id => text()();

  /// Owner user ID (auth user ID)
  TextColumn get userId => text()();

  /// Unique username (case-insensitive, used for search/mentions)
  TextColumn get username => text()();

  /// Display name
  TextColumn get displayName => text().withDefault(const Constant(''))();

  /// Optional bio/about text
  TextColumn get bio => text().withDefault(const Constant(''))();

  /// Optional profile image URL
  TextColumn get imageUrl => text().nullable()();

  /// Whether friend requests are enabled
  IntColumn get friendRequestsEnabled =>
      integer().withDefault(const Constant(1))();

  /// Last update timestamp (Unix milliseconds)
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  /// Per-field update timestamps for field-level merge conflict resolution.
  /// JSON map of {fieldName: timestampMs}. Empty map '{}' for legacy entities.
  TextColumn get fieldUpdatedAt =>
      text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}
