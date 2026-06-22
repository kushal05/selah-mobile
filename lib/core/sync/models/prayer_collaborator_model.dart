import '../../domain/enums/prayer_enums.dart';
import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for PrayerCollaborator
///
/// Represents a user who has access to a shared prayer
class PrayerCollaboratorModel implements SyncEntity {
  @override
  final String id;

  /// The prayer being collaborated on
  final String prayerId;

  /// The shared prayer record
  final String sharedPrayerId;

  /// Collaborator's user ID
  final String collaboratorUserId;

  /// Collaborator's username (denormalized)
  final String collaboratorUsername;

  /// Collaborator's role
  final CollaboratorRole role;

  /// User who added this collaborator
  final String addedByUserId;

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

  const PrayerCollaboratorModel({
    required this.id,
    required this.prayerId,
    required this.sharedPrayerId,
    required this.collaboratorUserId,
    required this.collaboratorUsername,
    required this.role,
    required this.addedByUserId,
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
      'sharedPrayerId': sharedPrayerId,
      'collaboratorUserId': collaboratorUserId,
      'collaboratorUsername': collaboratorUsername,
      'role': role.name,
      'addedByUserId': addedByUserId,
      'userId': userId,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory PrayerCollaboratorModel.fromJson(Map<String, dynamic> json) {
    return PrayerCollaboratorModel(
      id: (json['id'] ?? json['_id']) as String,
      prayerId: json['prayerId'] as String,
      sharedPrayerId: json['sharedPrayerId'] as String,
      collaboratorUserId: json['collaboratorUserId'] as String,
      collaboratorUsername: json['collaboratorUsername'] as String? ?? '',
      role: CollaboratorRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => CollaboratorRole.viewer,
      ),
      addedByUserId: json['addedByUserId'] as String,
      userId: json['userId'] as String,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  factory PrayerCollaboratorModel.create({
    required String id,
    required String prayerId,
    required String sharedPrayerId,
    required String collaboratorUserId,
    required String collaboratorUsername,
    required String addedByUserId,
    required String userId,
    CollaboratorRole role = CollaboratorRole.viewer,
  }) {
    final now = TestClock.now();
    return PrayerCollaboratorModel(
      id: id,
      prayerId: prayerId,
      sharedPrayerId: sharedPrayerId,
      collaboratorUserId: collaboratorUserId,
      collaboratorUsername: collaboratorUsername,
      role: role,
      addedByUserId: addedByUserId,
      userId: userId,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  PrayerCollaboratorModel copyWithRole(CollaboratorRole newRole) {
    return PrayerCollaboratorModel(
      id: id,
      prayerId: prayerId,
      sharedPrayerId: sharedPrayerId,
      collaboratorUserId: collaboratorUserId,
      collaboratorUsername: collaboratorUsername,
      role: newRole,
      addedByUserId: addedByUserId,
      userId: userId,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  PrayerCollaboratorModel softDelete() {
    return PrayerCollaboratorModel(
      id: id,
      prayerId: prayerId,
      sharedPrayerId: sharedPrayerId,
      collaboratorUserId: collaboratorUserId,
      collaboratorUsername: collaboratorUsername,
      role: role,
      addedByUserId: addedByUserId,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerCollaboratorModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() =>
      'PrayerCollaboratorModel(id: $id, user: $collaboratorUsername, '
      'role: ${role.name}, v$version)';
}
