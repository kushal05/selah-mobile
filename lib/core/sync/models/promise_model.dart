import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for Promise (Bible verses/promises)
///
/// Stores Bible promises with user notes
class PromiseModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID
  final String userId;

  /// Bible reference (e.g., "Jeremiah 29:11")
  final String reference;

  /// Full verse/promise text
  final String content;

  /// Short preview text for list display
  final String preview;

  /// User's personal notes about this promise
  final String notes;

  /// Optional category/tag
  final String? category;

  /// Whether this is a favorite promise
  final bool isFavorite;

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

  const PromiseModel({
    required this.id,
    required this.userId,
    required this.reference,
    required this.content,
    required this.preview,
    required this.notes,
    this.category,
    required this.isFavorite,
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
      'userId': userId,
      'reference': reference,
      'content': content,
      'preview': preview,
      'notes': notes,
      'category': category,
      'isFavorite': isFavorite,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory PromiseModel.fromJson(Map<String, dynamic> json) {
    return PromiseModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      reference: json['reference'] as String,
      content: json['content'] as String,
      preview: json['preview'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      category: json['category'] as String?,
      isFavorite: json['isFavorite'] == 1 || json['isFavorite'] == true,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  /// Create a new promise
  factory PromiseModel.create({
    required String id,
    required String userId,
    required String reference,
    required String content,
    String? preview,
    String notes = '',
    String? category,
    bool isFavorite = false,
  }) {
    final now = TestClock.now();
    return PromiseModel(
      id: id,
      userId: userId,
      reference: reference,
      content: content,
      preview: preview ?? _generatePreview(content),
      notes: notes,
      category: category,
      isFavorite: isFavorite,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  /// Generate preview from content (first 50 characters)
  static String _generatePreview(String content) {
    if (content.length <= 50) return content;
    return '${content.substring(0, 50)}...';
  }

  /// Create updated copy with incremented version
  PromiseModel copyWithUpdate({
    String? reference,
    String? content,
    String? preview,
    String? notes,
    String? category,
    bool? isFavorite,
  }) {
    return PromiseModel(
      id: id,
      userId: userId,
      reference: reference ?? this.reference,
      content: content ?? this.content,
      preview: preview ?? this.preview,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      isFavorite: isFavorite ?? this.isFavorite,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Toggle favorite status
  PromiseModel toggleFavorite() {
    return copyWithUpdate(isFavorite: !isFavorite);
  }

  /// Create soft-deleted copy
  PromiseModel softDelete() {
    return PromiseModel(
      id: id,
      userId: userId,
      reference: reference,
      content: content,
      preview: preview,
      notes: notes,
      category: category,
      isFavorite: isFavorite,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable)
  PromiseModel moveToTrash() {
    final now = TestClock.now();
    return PromiseModel(
      id: id,
      userId: userId,
      reference: reference,
      content: content,
      preview: preview,
      notes: notes,
      category: category,
      isFavorite: isFavorite,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  PromiseModel restoreFromTrash() {
    return PromiseModel(
      id: id,
      userId: userId,
      reference: reference,
      content: content,
      preview: preview,
      notes: notes,
      category: category,
      isFavorite: isFavorite,
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
      other is PromiseModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'PromiseModel(id: $id, reference: $reference, v$version)';
  }
}
