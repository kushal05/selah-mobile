import 'dart:math';

import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for SharedPrayer
///
/// Represents a prayer that has been shared with specific permissions
class SharedPrayerModel implements SyncEntity {
  @override
  final String id;

  /// The prayer being shared
  final String prayerId;

  /// User who shared the prayer
  final String sharedByUserId;

  /// Share code for link-based sharing
  final String shareCode;

  /// Whether collaborators can edit the prayer
  final bool allowEditing;

  /// Whether collaborators can log prayer activity
  final bool allowLogging;

  /// Whether collaborators can add updates
  final bool allowUpdates;

  /// Owner user ID
  final String userId;

  @override
  final int updatedAt;

  @override
  final int version;

  /// Soft delete flag
  final int deleted;

  @override
  final int? trashedAt;

  /// Creation timestamp
  final int createdAt;

  const SharedPrayerModel({
    required this.id,
    required this.prayerId,
    required this.sharedByUserId,
    required this.shareCode,
    required this.allowEditing,
    required this.allowLogging,
    required this.allowUpdates,
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
      'prayerId': prayerId,
      'sharedByUserId': sharedByUserId,
      'shareCode': shareCode,
      'allowEditing': allowEditing,
      'allowLogging': allowLogging,
      'allowUpdates': allowUpdates,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory SharedPrayerModel.fromJson(Map<String, dynamic> json) {
    return SharedPrayerModel(
      id: (json['id'] ?? json['_id']) as String,
      prayerId: json['prayerId'] as String,
      sharedByUserId: json['sharedByUserId'] as String,
      shareCode: json['shareCode'] as String? ?? '',
      allowEditing: _parseBool(json['allowEditing'], false),
      allowLogging: _parseBool(json['allowLogging'], true),
      allowUpdates: _parseBool(json['allowUpdates'], true),
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory SharedPrayerModel.create({
    required String id,
    required String prayerId,
    required String sharedByUserId,
    required String userId,
    bool allowEditing = false,
    bool allowLogging = true,
    bool allowUpdates = true,
  }) {
    final now = TestClock.now();
    return SharedPrayerModel(
      id: id,
      prayerId: prayerId,
      sharedByUserId: sharedByUserId,
      shareCode: _generateShareCode(),
      allowEditing: allowEditing,
      allowLogging: allowLogging,
      allowUpdates: allowUpdates,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  static String _generateShareCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  SharedPrayerModel copyWithPermissions({
    bool? allowEditing,
    bool? allowLogging,
    bool? allowUpdates,
  }) {
    return SharedPrayerModel(
      id: id,
      prayerId: prayerId,
      sharedByUserId: sharedByUserId,
      shareCode: shareCode,
      allowEditing: allowEditing ?? this.allowEditing,
      allowLogging: allowLogging ?? this.allowLogging,
      allowUpdates: allowUpdates ?? this.allowUpdates,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  SharedPrayerModel softDelete() {
    return SharedPrayerModel(
      id: id,
      prayerId: prayerId,
      sharedByUserId: sharedByUserId,
      shareCode: shareCode,
      allowEditing: allowEditing,
      allowLogging: allowLogging,
      allowUpdates: allowUpdates,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Parses deleted flag that may be bool (from API) or int (from local DB).
  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  static bool _parseBool(dynamic value, bool defaultValue) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    return defaultValue;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SharedPrayerModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'SharedPrayerModel(id: $id, prayerId: $prayerId, code: $shareCode, v$version)';
}
