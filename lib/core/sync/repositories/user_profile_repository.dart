import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../models/user_profile_model.dart';
import 'base_sync_repository.dart';

/// Repository for user profile operations with oplog-based sync.
class UserProfileRepository extends BaseSyncRepository<UserProfileModel> {
  final SyncDatabase _db;
  final String _deviceId;

  UserProfileRepository(this._db, this._deviceId);

  @override
  String get deviceId => _deviceId;

  @override
  OplogEntityType get entityType => OplogEntityType.userProfile;

  // ==================== READ OPERATIONS ====================

  Future<UserProfileModel?> getProfileById(String id) async {
    final row = await (_db.select(_db.userProfiles)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Future<UserProfileModel?> getProfileByUserId(String userId) async {
    final row = await (_db.select(_db.userProfiles)
          ..where((p) => p.userId.equals(userId) & p.deleted.equals(0)))
        .getSingleOrNull();
    return row != null ? _toModel(row) : null;
  }

  Stream<UserProfileModel?> watchProfileByUserId(String userId) {
    final query = _db.select(_db.userProfiles)
      ..where((p) => p.userId.equals(userId) & p.deleted.equals(0));
    return query.watchSingleOrNull().map((row) => row != null ? _toModel(row) : null);
  }

  // ==================== WRITE OPERATIONS ====================

  Future<UserProfileModel> createProfile({
    required String userId,
    required String username,
    String displayName = '',
    String bio = '',
    String? imageUrl,
    bool friendRequestsEnabled = true,
  }) async {
    final profile = UserProfileModel.create(
      id: generateId(),
      userId: userId,
      username: username,
      displayName: displayName,
      bio: bio,
      imageUrl: imageUrl,
      friendRequestsEnabled: friendRequestsEnabled,
    );

    final oplogEntry = createInsertOp(profile);

    await _db.transaction(() async {
      await _db.into(_db.userProfiles).insert(_toCompanion(profile));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return profile;
  }

  Future<UserProfileModel> updateProfile({
    required String id,
    String? username,
    String? displayName,
    String? bio,
    String? imageUrl,
    bool clearImageUrl = false,
    bool? friendRequestsEnabled,
  }) async {
    final existing = await getProfileById(id);
    if (existing == null) {
      throw UserProfileNotFoundException(id);
    }

    final updated = existing.copyWithUpdate(
      username: username,
      displayName: displayName,
      bio: bio,
      imageUrl: imageUrl,
      clearImageUrl: clearImageUrl,
      friendRequestsEnabled: friendRequestsEnabled,
    );

    final oplogEntry = createUpdateOp(updated);

    await _db.transaction(() async {
      await (_db.update(_db.userProfiles)..where((p) => p.id.equals(id)))
          .write(_toCompanion(updated));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });

    return updated;
  }

  Future<void> deleteProfile(String id) async {
    final existing = await getProfileById(id);
    if (existing == null) {
      throw UserProfileNotFoundException(id);
    }

    final deleted = existing.softDelete();
    final oplogEntry = createDeleteOp(deleted);

    await _db.transaction(() async {
      await (_db.update(_db.userProfiles)..where((p) => p.id.equals(id)))
          .write(_toCompanion(deleted));
      await _db.into(_db.oplog).insert(_oplogToCompanion(oplogEntry));
    });
  }

  // ==================== HELPER METHODS ====================

  UserProfileModel _toModel(UserProfile row) {
    return UserProfileModel(
      id: row.id,
      userId: row.userId,
      username: row.username,
      displayName: row.displayName,
      bio: row.bio,
      imageUrl: row.imageUrl,
      friendRequestsEnabled: row.friendRequestsEnabled == 1,
      updatedAt: row.updatedAt,
      version: row.version,
      deleted: row.deleted,
      createdAt: row.createdAt,
      fieldUpdatedAt: _parseFieldTimestamps(row.fieldUpdatedAt),
    );
  }

  UserProfilesCompanion _toCompanion(UserProfileModel model) {
    return UserProfilesCompanion(
      id: Value(model.id),
      userId: Value(model.userId),
      username: Value(model.username),
      displayName: Value(model.displayName),
      bio: Value(model.bio),
      imageUrl: Value(model.imageUrl),
      friendRequestsEnabled: Value(model.friendRequestsEnabled ? 1 : 0),
      updatedAt: Value(model.updatedAt),
      version: Value(model.version),
      deleted: Value(model.deleted),
      createdAt: Value(model.createdAt),
      fieldUpdatedAt: Value(jsonEncode(model.fieldUpdatedAt)),
    );
  }

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

  static Map<String, int> _parseFieldTimestamps(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }
}

class UserProfileNotFoundException implements Exception {
  final String profileId;
  UserProfileNotFoundException(this.profileId);

  @override
  String toString() => 'UserProfile not found: $profileId';
}
