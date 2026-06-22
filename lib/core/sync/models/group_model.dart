import 'dart:convert';
import 'dart:math';

import '../../domain/enums/group_enums.dart';
import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for Group
///
/// Represents a church community group
class GroupModel implements SyncEntity {
  @override
  final String id;

  /// Group name
  final String name;

  /// Group description
  final String description;

  /// Type of group
  final GroupType groupType;

  /// Optional group image URL
  final String? imageUrl;

  /// Code for joining the group
  final String joinCode;

  /// Join policy (codeOnly or open)
  final GroupJoinPolicy joinPolicy;

  /// User who created the group
  final String createdByUserId;

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

  /// Per-field update timestamps for field-level merge.
  final Map<String, int> fieldUpdatedAt;

  /// Fields eligible for field-level merge.
  static const mergeableFields = [
    'name',
    'description',
    'groupType',
    'imageUrl',
    'joinPolicy',
  ];

  const GroupModel({
    required this.id,
    required this.name,
    required this.description,
    required this.groupType,
    this.imageUrl,
    required this.joinCode,
    this.joinPolicy = GroupJoinPolicy.codeOnly,
    required this.createdByUserId,
    required this.userId,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.fieldUpdatedAt = const {},
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Get initials for avatar display
  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'groupType': groupType.name,
      'imageUrl': imageUrl,
      'joinCode': joinCode,
      'joinPolicy': joinPolicy.name,
      'createdByUserId': createdByUserId,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      'fieldUpdatedAt': fieldUpdatedAt,
    };
  }

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: (json['id'] ?? json['_id']) as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      groupType: GroupType.values.firstWhere(
        (t) => t.name == json['groupType'],
        orElse: () => GroupType.church,
      ),
      imageUrl: json['imageUrl'] as String?,
      joinCode: json['joinCode'] as String? ?? '',
      joinPolicy: GroupJoinPolicy.values.firstWhere(
        (p) => p.name == json['joinPolicy'],
        orElse: () => GroupJoinPolicy.codeOnly,
      ),
      createdByUserId: json['createdByUserId'] as String,
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
      fieldUpdatedAt: _parseFieldTimestamps(json['fieldUpdatedAt']),
    );
  }

  factory GroupModel.create({
    required String id,
    required String name,
    String description = '',
    GroupType groupType = GroupType.church,
    String? imageUrl,
    GroupJoinPolicy joinPolicy = GroupJoinPolicy.codeOnly,
    required String createdByUserId,
    required String userId,
  }) {
    final now = TestClock.now();
    return GroupModel(
      id: id,
      name: name,
      description: description,
      groupType: groupType,
      imageUrl: imageUrl,
      joinCode: _generateJoinCode(),
      joinPolicy: joinPolicy,
      createdByUserId: createdByUserId,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
      fieldUpdatedAt: {for (final f in mergeableFields) f: now},
    );
  }

  static String _generateJoinCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  GroupModel copyWithUpdate({
    String? name,
    String? description,
    GroupType? groupType,
    String? imageUrl,
    bool clearImageUrl = false,
    GroupJoinPolicy? joinPolicy,
  }) {
    final now = TestClock.now();
    final newFieldTimestamps = Map<String, int>.from(fieldUpdatedAt);
    if (name != null) newFieldTimestamps['name'] = now;
    if (description != null) newFieldTimestamps['description'] = now;
    if (groupType != null) newFieldTimestamps['groupType'] = now;
    if (imageUrl != null || clearImageUrl) {
      newFieldTimestamps['imageUrl'] = now;
    }
    if (joinPolicy != null) newFieldTimestamps['joinPolicy'] = now;

    return GroupModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      groupType: groupType ?? this.groupType,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      joinCode: joinCode,
      joinPolicy: joinPolicy ?? this.joinPolicy,
      createdByUserId: createdByUserId,
      userId: userId,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: newFieldTimestamps,
    );
  }

  GroupModel softDelete() {
    return GroupModel(
      id: id,
      name: name,
      description: description,
      groupType: groupType,
      imageUrl: imageUrl,
      joinCode: joinCode,
      joinPolicy: joinPolicy,
      createdByUserId: createdByUserId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  static Map<String, int> _parseFieldTimestamps(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) {
      try {
        return value.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {
        return {};
      }
    }
    return {};
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
      other is GroupModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'GroupModel(id: $id, name: $name, type: ${groupType.name}, v$version)';
}
