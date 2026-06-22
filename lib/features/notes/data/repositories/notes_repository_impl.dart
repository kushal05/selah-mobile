import 'package:drift/drift.dart' as drift;

import '../../../../core/database/app_database.dart';
import '../../domain/models/note.dart' as domain;
import '../../domain/repositories/notes_repository.dart';
import '../converters/document_converter.dart';

/// Implementation of NotesRepository using Drift
class NotesRepositoryImpl implements NotesRepository {
  final AppDatabase _database;

  NotesRepositoryImpl(this._database);

  @override
  Future<List<domain.Note>> getAllNotes() async {
    final notes = await _database.notesDao.getAllNotes();
    return notes.map(_toDomainNote).toList();
  }

  @override
  Future<domain.Note?> getNoteById(String id) async {
    final note = await _database.notesDao.getNoteById(id);
    return note != null ? _toDomainNote(note) : null;
  }

  @override
  Stream<domain.Note?> watchNoteById(String id) {
    return _database.notesDao.watchNoteById(id).map(
          (note) => note != null ? _toDomainNote(note) : null,
        );
  }

  @override
  Stream<List<domain.Note>> watchAllNotes() {
    return _database.notesDao.watchAllNotes().map(
          (notes) => notes.map(_toDomainNote).toList(),
        );
  }

  @override
  Future<void> createNote(domain.Note note) async {
    final companion = _toNotesCompanion(note);
    await _database.notesDao.createNote(companion);
  }

  @override
  Future<void> updateNote(domain.Note note) async {
    final companion = _toNotesCompanion(note);
    await _database.notesDao.updateNote(companion);
  }

  @override
  Future<void> deleteNote(String id) async {
    await _database.notesDao.deleteNote(id);
  }

  @override
  Future<void> trashNote(String id) async {
    // Legacy DB: no trash support, fall through to delete
    await _database.notesDao.deleteNote(id);
  }

  @override
  Future<void> restoreNote(String id) async {
    // Legacy DB: no trash support, no-op
  }

  @override
  Future<List<domain.Note>> searchNotes(String query) async {
    final notes = await _database.notesDao.searchNotes(query);
    return notes.map(_toDomainNote).toList();
  }

  @override
  Future<List<domain.Note>> getNotesByPreacher(String preacherId) async {
    final notes = await _database.notesDao.getNotesByPreacher(preacherId);
    return notes.map(_toDomainNote).toList();
  }

  @override
  Future<List<domain.Note>> getNotesWithTag(String tagId) async {
    final noteIds = await _database.metadataDao.getNoteIdsWithTag(tagId);
    final notes = <domain.Note>[];

    for (final noteId in noteIds) {
      final note = await getNoteById(noteId);
      if (note != null) {
        notes.add(note);
      }
    }

    return notes;
  }

  @override
  Future<List<String>> getTagsForNote(String noteId) async {
    final tags = await _database.metadataDao.getTagsForNote(noteId);
    return tags.map((tag) => tag.id).toList();
  }

  @override
  Future<void> setTagsForNote(String noteId, List<String> tagIds) async {
    await _database.metadataDao.setTagsForNote(noteId, tagIds);
  }

  @override
  Future<void> addTagToNote(String noteId, String tagId) async {
    await _database.metadataDao.addTagToNote(noteId, tagId);
  }

  @override
  Future<void> removeTagFromNote(String noteId, String tagId) async {
    await _database.metadataDao.removeTagFromNote(noteId, tagId);
  }

  @override
  Future<List<domain.Note>> getNotesByFolder(String? folderId) async {
    final notes = await _database.notesDao.getNotesByFolder(folderId);
    return notes.map(_toDomainNote).toList();
  }

  @override
  Future<int> moveNotes(List<String> noteIds, String targetFolderId) async {
    return await _database.notesDao.moveNotes(noteIds, targetFolderId);
  }

  @override
  Future<void> moveNotesFromFolder(String sourceFolderId, String? targetFolderId) async {
    await _database.notesDao.moveNotesFromFolder(sourceFolderId, targetFolderId);
  }

  @override
  Future<void> deleteNotesInFolder(String folderId) async {
    await _database.notesDao.deleteNotesInFolder(folderId);
  }

  @override
  Future<int> getNoteCountInFolder(String? folderId) async {
    return await _database.notesDao.getNoteCountInFolder(folderId);
  }

  @override
  Future<void> toggleCheckboxBlock(String noteId, String blockId) {
    // Legacy AppDatabase-backed impl has no block-level support.
    // The active path uses SyncNotesRepositoryAdapter over SyncDatabase.
    throw UnimplementedError(
      'toggleCheckboxBlock: legacy NotesRepositoryImpl is retained for '
      'schema reference only; block-level edits flow through the sync '
      'adapter over SyncDatabase.',
    );
  }

  // ==================== Mappers ====================

  /// Convert Drift Note to domain Note
  domain.Note _toDomainNote(Note driftNote) {
    final document = DocumentConverter.fromJsonString(driftNote.documentJson);

    return domain.Note(
      id: driftNote.id,
      title: driftNote.title,
      document: document,
      createdAt: driftNote.createdAt,
      updatedAt: driftNote.updatedAt,
      version: driftNote.version,
      preacherId: driftNote.preacherId,
      folderId: driftNote.folderId,
      noteDate: driftNote.noteDate,
    );
  }

  /// Convert domain Note to Drift NotesCompanion
  NotesCompanion _toNotesCompanion(domain.Note note) {
    final documentJson = DocumentConverter.toJsonString(note.document);

    return NotesCompanion(
      id: drift.Value(note.id),
      title: drift.Value(note.title),
      documentJson: drift.Value(documentJson),
      createdAt: drift.Value(note.createdAt),
      updatedAt: drift.Value(note.updatedAt),
      version: drift.Value(note.version),
      preacherId: drift.Value(note.preacherId),
      folderId: drift.Value(note.folderId),
      noteDate: drift.Value(note.noteDate),
    );
  }
}
