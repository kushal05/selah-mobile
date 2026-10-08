import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for SongTag junction (sync-enabled)
///
/// Each song-tag association has its own stable ID for oplog tracking.
class SongTagModel implements SyncEntity {
  @override
  final String id;

  final String songId;
  final String tagId;
  final String userId;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  /// How strongly the song carries the tag, for ranking search: 3 a central
  /// theme, 2 a clear theme, 1 present but minor.
  final int weight;

  /// Weight given to links made in the app, and to any older payload or row
  /// without one.
  static const defaultWeight = 2;

  /// [value] read from storage or a payload, held to 1-3. Any finite number
  /// counts (a JSON encoder may write 3 as 3.0); anything else is the default.
  /// Never throws: this runs inside the sync apply, where a throw fails the
  /// whole operation.
  static int clampWeight(Object? value) => value is num && value.isFinite
      ? value.round().clamp(1, 3)
      : defaultWeight;

  const SongTagModel({
    required this.id,
    required this.songId,
    required this.tagId,
    required this.userId,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.weight = defaultWeight,
  });

  @override
  bool get isDeleted => deleted == 1;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'songId': songId,
      'tagId': tagId,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      // Always sent, null included: the server's UPDATE leaves absent keys
      // untouched, so omitting it meant a restored link stayed trashed there.
      'trashedAt': trashedAt,
      'createdAt': createdAt,
      'weight': weight,
    };
  }

  factory SongTagModel.fromJson(Map<String, dynamic> json) {
    return SongTagModel(
      id: (json['id'] ?? json['_id']) as String,
      songId: json['songId'] as String,
      tagId: json['tagId'] as String,
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
      weight: clampWeight(json['weight']),
    );
  }

  factory SongTagModel.create({
    required String id,
    required String songId,
    required String tagId,
    required String userId,
  }) {
    final now = TestClock.now();
    return SongTagModel(
      id: id,
      songId: songId,
      tagId: tagId,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  SongTagModel softDelete() {
    return SongTagModel(
      id: id,
      songId: songId,
      tagId: tagId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      weight: weight,
    );
  }

  /// Move to trash (recoverable, cascade from parent)
  SongTagModel moveToTrash() {
    final now = TestClock.now();
    return SongTagModel(
      id: id,
      songId: songId,
      tagId: tagId,
      userId: userId,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
      weight: weight,
    );
  }

  /// Restore from trash
  SongTagModel restoreFromTrash() {
    return SongTagModel(
      id: id,
      songId: songId,
      tagId: tagId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
      weight: weight,
    );
  }

  /// Bring a deleted link back: same row, higher version. Re-creating it at
  /// version 1 under the old id is ignored by the server (its INSERT is
  /// ON CONFLICT DO NOTHING), so the tag stayed removed on every other device.
  SongTagModel revive() {
    return SongTagModel(
      id: id,
      songId: songId,
      tagId: tagId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 0,
      trashedAt: null,
      createdAt: createdAt,
      weight: weight,
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
      other is SongTagModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;
}
