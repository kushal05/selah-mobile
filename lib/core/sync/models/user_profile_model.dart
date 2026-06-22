import 'dart:convert';

import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for UserProfile
///
/// Stores the user's public profile with username for the social/friends system
class UserProfileModel implements SyncEntity {
  @override
  final String id;

  /// Auth user ID
  final String userId;

  /// Unique username (case-insensitive)
  final String username;

  /// Display name
  final String displayName;

  /// Optional bio/about text
  final String bio;

  /// Optional profile image URL
  final String? imageUrl;

  /// Whether friend requests are enabled
  final bool friendRequestsEnabled;

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
    'username',
    'displayName',
    'bio',
    'imageUrl',
    'friendRequestsEnabled',
  ];

  const UserProfileModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.bio,
    this.imageUrl,
    required this.friendRequestsEnabled,
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
    final name = displayName.isNotEmpty ? displayName : username;
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'username': username,
      'displayName': displayName,
      'bio': bio,
      'imageUrl': imageUrl,
      'friendRequestsEnabled': friendRequestsEnabled,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      'fieldUpdatedAt': fieldUpdatedAt,
    };
  }

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      friendRequestsEnabled: _parseBool(json['friendRequestsEnabled'], true),
      updatedAt: json['updatedAt'] as int? ?? 0,
      version: json['version'] as int? ?? 1,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int? ?? json['updatedAt'] as int? ?? 0,
      fieldUpdatedAt: _parseFieldTimestamps(json['fieldUpdatedAt']),
    );
  }

  /// Create from a server search result which only contains projected fields
  /// (userId, username, displayName, bio, imageUrl).
  factory UserProfileModel.fromSearchResult(Map<String, dynamic> json) {
    final now = TestClock.now();
    return UserProfileModel(
      id: json['userId'] as String,
      userId: json['userId'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      friendRequestsEnabled: _parseBool(json['friendRequestsEnabled'], true),
      updatedAt: now,
      version: 0,
      deleted: 0,
      createdAt: now,
    );
  }

  factory UserProfileModel.create({
    required String id,
    required String userId,
    required String username,
    String displayName = '',
    String bio = '',
    String? imageUrl,
    bool friendRequestsEnabled = true,
  }) {
    final now = TestClock.now();
    return UserProfileModel(
      id: id,
      userId: userId,
      username: username,
      displayName: displayName,
      bio: bio,
      imageUrl: imageUrl,
      friendRequestsEnabled: friendRequestsEnabled,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
      fieldUpdatedAt: {for (final f in mergeableFields) f: now},
    );
  }

  UserProfileModel copyWithUpdate({
    String? username,
    String? displayName,
    String? bio,
    String? imageUrl,
    bool clearImageUrl = false,
    bool? friendRequestsEnabled,
  }) {
    final now = TestClock.now();
    final newFieldTimestamps = Map<String, int>.from(fieldUpdatedAt);
    if (username != null) newFieldTimestamps['username'] = now;
    if (displayName != null) newFieldTimestamps['displayName'] = now;
    if (bio != null) newFieldTimestamps['bio'] = now;
    if (imageUrl != null || clearImageUrl) {
      newFieldTimestamps['imageUrl'] = now;
    }
    if (friendRequestsEnabled != null) {
      newFieldTimestamps['friendRequestsEnabled'] = now;
    }

    return UserProfileModel(
      id: id,
      userId: userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      friendRequestsEnabled:
          friendRequestsEnabled ?? this.friendRequestsEnabled,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: newFieldTimestamps,
    );
  }

  UserProfileModel softDelete() {
    return UserProfileModel(
      id: id,
      userId: userId,
      username: username,
      displayName: displayName,
      bio: bio,
      imageUrl: imageUrl,
      friendRequestsEnabled: friendRequestsEnabled,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  /// Parses deleted flag that may be bool (from API) or int (from local DB).
  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  /// Parses a value that may be bool (from API) or int (from local Drift DB).
  static bool _parseBool(dynamic value, bool defaultValue) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    return defaultValue;
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'UserProfileModel(id: $id, username: $username, v$version)';
}
