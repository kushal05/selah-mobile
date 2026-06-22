import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for Person
///
/// Stores people to pray for with contact information
class PersonModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID
  final String userId;

  /// Person's name
  final String name;

  /// Relationship/group (e.g., "Family", "Friend", "Church Member")
  final String relation;

  /// Church or organization the person belongs to
  final String? church;

  /// Optional email address
  final String? email;

  /// Optional phone number
  final String? phone;

  /// Notes about this person or prayer requests for them
  final String notes;

  /// Optional profile image URL or path
  final String? imageUrl;

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

  const PersonModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.relation,
    this.church,
    this.email,
    this.phone,
    required this.notes,
    this.imageUrl,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Get initials for avatar display
  String get initials {
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
      'name': name,
      'relation': relation,
      'church': church,
      'email': email,
      'phone': phone,
      'notes': notes,
      'imageUrl': imageUrl,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory PersonModel.fromJson(Map<String, dynamic> json) {
    return PersonModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      relation: json['relation'] as String? ?? '',
      church: json['church'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      notes: json['notes'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  /// Create a new person
  factory PersonModel.create({
    required String id,
    required String userId,
    required String name,
    String relation = '',
    String? church,
    String? email,
    String? phone,
    String notes = '',
    String? imageUrl,
  }) {
    final now = TestClock.now();
    return PersonModel(
      id: id,
      userId: userId,
      name: name,
      relation: relation,
      church: church,
      email: email,
      phone: phone,
      notes: notes,
      imageUrl: imageUrl,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  /// Create updated copy with incremented version
  PersonModel copyWithUpdate({
    String? name,
    String? relation,
    String? church,
    String? email,
    String? phone,
    String? notes,
    String? imageUrl,
  }) {
    return PersonModel(
      id: id,
      userId: userId,
      name: name ?? this.name,
      relation: relation ?? this.relation,
      church: church ?? this.church,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      imageUrl: imageUrl ?? this.imageUrl,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Create soft-deleted copy
  PersonModel softDelete() {
    return PersonModel(
      id: id,
      userId: userId,
      name: name,
      relation: relation,
      church: church,
      email: email,
      phone: phone,
      notes: notes,
      imageUrl: imageUrl,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable)
  PersonModel moveToTrash() {
    final now = TestClock.now();
    return PersonModel(
      id: id,
      userId: userId,
      name: name,
      relation: relation,
      church: church,
      email: email,
      phone: phone,
      notes: notes,
      imageUrl: imageUrl,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  PersonModel restoreFromTrash() {
    return PersonModel(
      id: id,
      userId: userId,
      name: name,
      relation: relation,
      church: church,
      email: email,
      phone: phone,
      notes: notes,
      imageUrl: imageUrl,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
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
      other is PersonModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'PersonModel(id: $id, name: $name, relation: $relation, v$version)';
  }
}
