import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Domain model for BibleReferenceHistory
///
/// Tracks every Bible reference opened by the user.
/// Append-heavy entity — most writes are inserts, updates only for dedup.
class BibleReferenceHistoryModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID
  final String userId;

  /// Book name (e.g., "John", "Genesis")
  final String book;

  /// Chapter number
  final int chapter;

  /// Starting verse (null for chapter-only views)
  final int? verseStart;

  /// Ending verse (null for single verse or chapter-only)
  final int? verseEnd;

  /// Bible translation (e.g., "KJV", "NIV")
  final String translation;

  /// Timestamp when the reference was opened (Unix milliseconds)
  final int openedAt;

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

  const BibleReferenceHistoryModel({
    required this.id,
    required this.userId,
    required this.book,
    required this.chapter,
    this.verseStart,
    this.verseEnd,
    required this.translation,
    required this.openedAt,
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
      'book': book,
      'chapter': chapter,
      if (verseStart != null) 'verseStart': verseStart,
      if (verseEnd != null) 'verseEnd': verseEnd,
      'translation': translation,
      'openedAt': openedAt,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory BibleReferenceHistoryModel.fromJson(Map<String, dynamic> json) {
    return BibleReferenceHistoryModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      book: json['book'] as String,
      chapter: json['chapter'] as int,
      verseStart: json['verseStart'] as int?,
      verseEnd: json['verseEnd'] as int?,
      translation: json['translation'] as String,
      openedAt: json['openedAt'] as int,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  /// Create a new Bible reference history entry
  factory BibleReferenceHistoryModel.create({
    required String id,
    required String userId,
    required String book,
    required int chapter,
    int? verseStart,
    int? verseEnd,
    required String translation,
  }) {
    final now = TestClock.now();
    return BibleReferenceHistoryModel(
      id: id,
      userId: userId,
      book: book,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
      translation: translation,
      openedAt: now,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  /// Create updated copy with bumped openedAt timestamp (for dedup)
  BibleReferenceHistoryModel copyWithUpdate({
    int? openedAt,
  }) {
    final now = TestClock.now();
    return BibleReferenceHistoryModel(
      id: id,
      userId: userId,
      book: book,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
      translation: translation,
      openedAt: openedAt ?? now,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Create soft-deleted copy
  BibleReferenceHistoryModel softDelete() {
    return BibleReferenceHistoryModel(
      id: id,
      userId: userId,
      book: book,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
      translation: translation,
      openedAt: openedAt,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Formatted reference string (e.g., "John 3:16" or "John 3:16-18" or "John 3")
  String get formattedReference {
    final buffer = StringBuffer('$book $chapter');
    if (verseStart != null) {
      buffer.write(':$verseStart');
      if (verseEnd != null && verseEnd != verseStart) {
        buffer.write('-$verseEnd');
      }
    }
    return buffer.toString();
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
      other is BibleReferenceHistoryModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'BibleReferenceHistoryModel(id: $id, ref: $formattedReference, v$version)';
  }
}
