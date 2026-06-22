import 'dart:convert';

import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// A single chord line mapped to a lyric line by index.
/// Stored structurally, never embedded in lyrics text.
class ChordLine {
  /// Index of the lyric line this chord line maps to
  final int lineIndex;

  /// Raw chord string (e.g. "G  D  Em  C")
  final String rawChords;

  const ChordLine({required this.lineIndex, required this.rawChords});

  Map<String, dynamic> toJson() => {
        'lineIndex': lineIndex,
        'rawChords': rawChords,
      };

  factory ChordLine.fromJson(Map<String, dynamic> json) {
    return ChordLine(
      lineIndex: json['lineIndex'] as int,
      rawChords: json['rawChords'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordLine &&
          lineIndex == other.lineIndex &&
          rawChords == other.rawChords;

  @override
  int get hashCode => Object.hash(lineIndex, rawChords);
}

/// Domain model for Song
///
/// Stores song lyrics and chord annotations with folder organization.
/// Chords are stored structurally in [chordLinesList], separate from lyrics.
/// The legacy [chords] field (inline [chord] notation) is preserved for
/// backward compatibility but new songs should use [chordLinesList].
class SongModel implements SyncEntity {
  @override
  final String id;

  /// Owner user ID
  final String userId;

  /// Song title (mandatory)
  final String title;

  /// Folder ID for organization (null for root)
  final String? folderId;

  /// Clean lyrics content (plain text with line breaks)
  final String lyrics;

  /// Legacy: lyrics with inline chord annotations ([G]Amazing [C]grace)
  final String chords;

  /// Musical scale/key of the song (e.g. "C", "Dm", "F#", "Bb")
  final String scale;

  /// Structured chord lines as JSON string.
  /// Parsed via [chordLinesList]. Each ChordLine maps to a lyric line by index.
  final String chordLinesJson;

  /// Primary language of the song
  final String language;

  /// Optional songbook/collection identifier
  final String? book;

  /// Preview text (auto-generated from lyrics)
  final String preview;

  /// User-defined tags (comma-separated)
  final String tags;

  /// Free-form notes or references related to the song
  final String notes;

  /// Whether song has chord annotations (structured or legacy)
  final bool hasChords;

  /// Favorite flag
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

  const SongModel({
    required this.id,
    required this.userId,
    required this.title,
    this.folderId,
    required this.lyrics,
    required this.chords,
    this.scale = '',
    this.chordLinesJson = '',
    required this.language,
    this.book,
    required this.preview,
    required this.tags,
    this.notes = '',
    required this.hasChords,
    required this.isFavorite,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
  });

  @override
  bool get isDeleted => deleted == 1;

  /// Get tags as a list
  List<String> get tagList =>
      tags.isEmpty ? [] : tags.split(',').map((t) => t.trim()).toList();

  /// Parse structured chord lines from JSON
  List<ChordLine> get chordLinesList {
    if (chordLinesJson.isEmpty) return [];
    try {
      final list = jsonDecode(chordLinesJson) as List? ?? [];
      return list
          .map((e) => ChordLine.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Whether this song uses structured chord lines (vs legacy inline)
  bool get hasStructuredChords => chordLinesJson.isNotEmpty;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'folderId': folderId,
      'lyrics': lyrics,
      'chords': chords,
      'scale': scale,
      'chordLines': chordLinesJson,
      'language': language,
      'book': book,
      'preview': preview,
      'tags': tags,
      'notes': notes,
      'hasChords': hasChords,
      'isFavorite': isFavorite,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
    };
  }

  factory SongModel.fromJson(Map<String, dynamic> json) {
    return SongModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      folderId: json['folderId'] as String?,
      lyrics: json['lyrics'] as String? ?? '',
      chords: json['chords'] as String? ?? '',
      scale: json['scale'] as String? ?? '',
      chordLinesJson: json['chordLines'] as String? ?? '',
      language: json['language'] as String? ?? 'English',
      book: json['book'] as String?,
      preview: json['preview'] as String? ?? '',
      tags: json['tags'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      hasChords: _parseBool(json['hasChords']),
      isFavorite: _parseBool(json['isFavorite']),
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
    );
  }

  /// Safely parse a boolean from JSON that may be bool, int (0/1), or null.
  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is int) return value == 1;
    return false;
  }

  /// Parses deleted flag that may be bool (from API) or int (from local DB).
  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  /// Create a new song
  factory SongModel.create({
    required String id,
    required String userId,
    required String title,
    String? folderId,
    String lyrics = '',
    String chords = '',
    String scale = '',
    List<ChordLine> chordLines = const [],
    String language = 'English',
    String? book,
    String tags = '',
    String notes = '',
  }) {
    final now = TestClock.now();
    final preview = _generatePreview(lyrics);
    final chordLinesJson =
        chordLines.isEmpty ? '' : jsonEncode(chordLines.map((c) => c.toJson()).toList());
    final hasChords = chords.isNotEmpty || chordLinesJson.isNotEmpty;

    return SongModel(
      id: id,
      userId: userId,
      title: title,
      folderId: folderId,
      lyrics: lyrics,
      chords: chords,
      scale: scale,
      chordLinesJson: chordLinesJson,
      language: language,
      book: book,
      preview: preview,
      tags: tags,
      notes: notes,
      hasChords: hasChords,
      isFavorite: false,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  /// Create updated copy with incremented version.
  /// To explicitly clear nullable fields (folderId, book), pass
  /// [clearFolderId] or [clearBook] as true.
  SongModel copyWithUpdate({
    String? title,
    String? folderId,
    bool clearFolderId = false,
    String? lyrics,
    String? chords,
    String? scale,
    List<ChordLine>? chordLines,
    String? language,
    String? book,
    bool clearBook = false,
    String? tags,
    String? notes,
    bool? isFavorite,
  }) {
    final newLyrics = lyrics ?? this.lyrics;
    final newChords = chords ?? this.chords;
    final newChordLinesJson = chordLines != null
        ? (chordLines.isEmpty
            ? ''
            : jsonEncode(chordLines.map((c) => c.toJson()).toList()))
        : chordLinesJson;

    return SongModel(
      id: id,
      userId: userId,
      title: title ?? this.title,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      lyrics: newLyrics,
      chords: newChords,
      scale: scale ?? this.scale,
      chordLinesJson: newChordLinesJson,
      language: language ?? this.language,
      book: clearBook ? null : (book ?? this.book),
      preview: lyrics != null ? _generatePreview(newLyrics) : preview,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      hasChords: newChords.isNotEmpty || newChordLinesJson.isNotEmpty,
      isFavorite: isFavorite ?? this.isFavorite,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Toggle favorite status
  SongModel toggleFavorite() {
    return copyWithUpdate(isFavorite: !isFavorite);
  }

  /// Create soft-deleted copy
  SongModel softDelete() {
    return SongModel(
      id: id,
      userId: userId,
      title: title,
      folderId: folderId,
      lyrics: lyrics,
      chords: chords,
      scale: scale,
      chordLinesJson: chordLinesJson,
      language: language,
      book: book,
      preview: preview,
      tags: tags,
      notes: notes,
      hasChords: hasChords,
      isFavorite: isFavorite,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
    );
  }

  /// Move to trash (recoverable)
  SongModel moveToTrash() {
    final now = TestClock.now();
    return SongModel(
      id: id,
      userId: userId,
      title: title,
      folderId: folderId,
      lyrics: lyrics,
      chords: chords,
      scale: scale,
      chordLinesJson: chordLinesJson,
      language: language,
      book: book,
      preview: preview,
      tags: tags,
      notes: notes,
      hasChords: hasChords,
      isFavorite: isFavorite,
      updatedAt: now,
      version: version + 1,
      deleted: deleted,
      trashedAt: now,
      createdAt: createdAt,
    );
  }

  /// Restore from trash
  SongModel restoreFromTrash() {
    return SongModel(
      id: id,
      userId: userId,
      title: title,
      folderId: folderId,
      lyrics: lyrics,
      chords: chords,
      scale: scale,
      chordLinesJson: chordLinesJson,
      language: language,
      book: book,
      preview: preview,
      tags: tags,
      notes: notes,
      hasChords: hasChords,
      isFavorite: isFavorite,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: null,
      createdAt: createdAt,
    );
  }

  /// Generate preview from lyrics (first ~50 chars)
  static String _generatePreview(String lyrics) {
    if (lyrics.isEmpty) return '';
    final cleaned = lyrics.replaceAll('\n', ' ').trim();
    if (cleaned.length <= 50) return cleaned;
    return '${cleaned.substring(0, 47)}...';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => Object.hash(id, version);

  @override
  String toString() {
    return 'SongModel(id: $id, title: $title, scale: $scale, language: $language, v$version)';
  }
}
