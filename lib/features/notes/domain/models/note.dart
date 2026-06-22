import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'editor_document.dart';

/// Note entity (domain model)
@immutable
class Note extends Equatable {
  /// Unique identifier
  final String id;

  /// Note title
  final String title;

  /// Editor document containing blocks
  final EditorDocument document;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last update timestamp
  final DateTime updatedAt;

  /// Version for conflict resolution
  final int version;

  /// Associated preacher ID (optional)
  final String? preacherId;

  /// Associated folder ID (optional - null means root level)
  final String? folderId;

  /// Associated date (e.g., sermon date)
  final DateTime? noteDate;

  const Note({
    required this.id,
    required this.title,
    required this.document,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.preacherId,
    this.folderId,
    this.noteDate,
  });

  /// Create a new note with default values
  factory Note.create({
    required String id,
    String? title,
    EditorDocument? document,
  }) {
    final now = DateTime.now();
    return Note(
      id: id,
      title: title ?? 'Untitled Note',
      document: document ?? EditorDocument.empty(),
      createdAt: now,
      updatedAt: now,
      version: 1,
    );
  }

  /// Copy with modifications
  Note copyWith({
    String? id,
    String? title,
    EditorDocument? document,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    String? preacherId,
    String? folderId,
    DateTime? noteDate,
    bool clearFolderId = false,
    bool clearPreacherId = false,
    bool clearNoteDate = false,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      document: document ?? this.document,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      preacherId: clearPreacherId ? null : (preacherId ?? this.preacherId),
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      noteDate: clearNoteDate ? null : (noteDate ?? this.noteDate),
    );
  }

  /// Update the note with a new timestamp and version
  Note update({
    String? title,
    EditorDocument? document,
    String? preacherId,
    String? folderId,
    DateTime? noteDate,
    bool clearPreacherId = false,
    bool clearNoteDate = false,
  }) {
    return copyWith(
      title: title,
      document: document,
      preacherId: preacherId,
      folderId: folderId,
      noteDate: noteDate,
      clearPreacherId: clearPreacherId,
      clearNoteDate: clearNoteDate,
      updatedAt: DateTime.now(),
      version: version + 1,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        document,
        createdAt,
        updatedAt,
        version,
        preacherId,
        folderId,
        noteDate,
      ];

  @override
  String toString() => 'Note(id: $id, title: $title, version: $version)';
}
