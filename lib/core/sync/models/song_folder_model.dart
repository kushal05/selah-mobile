import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for SongFolder junction (sync-enabled)
///
/// Each song-folder association has its own stable ID for oplog tracking.
/// The song's songbooks are `songs.folder_id` plus every live link.
class SongFolderModel implements SyncEntity {
  @override
  final String id;

  final String songId;
  final String folderId;
  final String userId;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  const SongFolderModel({
    required this.id,
    required this.songId,
    required this.folderId,
    required this.userId,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'songId': songId,
      'folderId': folderId,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      // Always sent, null included: the server's UPDATE leaves keys that are
      // absent untouched, so omitting it would never clear a trashed link.
      'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory SongFolderModel.fromJson(Map<String, dynamic> json) {
    return SongFolderModel(
      id: (json['id'] ?? json['_id']) as String,
      songId: json['songId'] as String,
      folderId: json['folderId'] as String,
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory SongFolderModel.create({
    required String id,
    required String songId,
    required String folderId,
    required String userId,
  }) {
    final now = TestClock.now();
    return SongFolderModel(
      id: id,
      songId: songId,
      folderId: folderId,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  SongFolderModel softDelete() {
    return SongFolderModel(
      id: id,
      songId: songId,
      folderId: folderId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable, cascade from parent)
  SongFolderModel moveToTrash() {
    final now = TestClock.now();
    return SongFolderModel(
      id: id,
      songId: songId,
      folderId: folderId,
      userId: userId,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  SongFolderModel restoreFromTrash() {
    return SongFolderModel(
      id: id,
      songId: songId,
      folderId: folderId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
    );
  }

  /// Bring a deleted or trashed link back. Reuses the row (same id) at a
  /// higher version: re-inserting it at version 1 would lose to the server's
  /// copy, which already has a higher version.
  SongFolderModel revive() {
    return SongFolderModel(
      id: id,
      songId: songId,
      folderId: folderId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 0,
      trashedAt: null,
      createdAt: createdAt,
    );
  }

  /// Parses deleted flag that may be bool (from API) or int (from local DB).
  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongFolderModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;
}
