import 'package:drift/drift.dart';

/// Universal access control table for any content entity.
///
/// Replaces ad-hoc visibility fields (folder.visibility, SharedPrayers,
/// PrayerCollaborators) with a single, extensible ACL system.
///
/// Access resolution order:
/// 1. owner  — entity.userId == viewer
/// 2. user   — targetId == viewerId
/// 3. friend — accessType == 'friend' AND viewer is friend of owner
/// 4. group  — accessType == 'group' AND viewer ∈ group_members(targetId)
/// 5. public — accessType == 'public'
///
/// Folder inheritance: children inherit parent folder's access rules.
class EntityAccess extends Table {
  /// Primary key — stable UUID
  TextColumn get id => text()();

  /// Type of entity being shared: note, song, prayer, promise, folder
  TextColumn get entityType => text()();

  /// ID of the entity being shared
  TextColumn get entityId => text()();

  /// Access grant type: owner, user, friend, group, public
  TextColumn get accessType => text()();

  /// Target of the grant:
  /// - userId when accessType = 'user'
  /// - groupId when accessType = 'group'
  /// - null when accessType = 'owner', 'friend', or 'public'
  TextColumn get targetId => text().nullable()();

  /// Permission level: owner, admin, editor, viewer
  TextColumn get role => text().withDefault(const Constant('viewer'))();

  /// Owner user ID — sync partition key
  TextColumn get userId => text()();

  /// Last update timestamp (Unix milliseconds)
  IntColumn get updatedAt => integer()();

  /// Version number for optimistic locking
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Soft delete flag (0 = active, 1 = deleted)
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// Creation timestamp (Unix milliseconds)
  IntColumn get createdAt => integer()();

  /// Acceptance timestamp (Unix milliseconds).
  ///
  /// - Owner/friend/group/public grants: set to createdAt (implicit accept).
  /// - Tier-2 `user` grants: NULL until the recipient explicitly accepts
  ///   from their inbox, at which point the permission gate activates.
  IntColumn get acceptedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
