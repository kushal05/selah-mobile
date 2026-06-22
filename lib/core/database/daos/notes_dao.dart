import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/notes_table.dart';

part 'notes_dao.g.dart';

/// Data Access Object for Notes
/// Handles CRUD operations for notes
@DriftAccessor(tables: [Notes])
class NotesDao extends DatabaseAccessor<AppDatabase> with _$NotesDaoMixin {
  NotesDao(super.db);

  /// Get all notes ordered by updated date (most recent first)
  Future<List<Note>> getAllNotes() {
    return (select(notes)
          ..orderBy([
            (note) => OrderingTerm(
                expression: note.updatedAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Get a note by ID
  Future<Note?> getNoteById(String id) {
    return (select(notes)..where((note) => note.id.equals(id))).getSingleOrNull();
  }

  /// Watch a note by ID (reactive stream)
  Stream<Note?> watchNoteById(String id) {
    return (select(notes)..where((note) => note.id.equals(id))).watchSingleOrNull();
  }

  /// Watch all notes (reactive stream)
  Stream<List<Note>> watchAllNotes() {
    return (select(notes)
          ..orderBy([
            (note) => OrderingTerm(
                expression: note.updatedAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  /// Insert or update a note
  Future<int> upsertNote(NotesCompanion note) {
    return into(notes).insertOnConflictUpdate(note);
  }

  /// Create a new note
  Future<int> createNote(NotesCompanion note) {
    return into(notes).insert(note);
  }

  /// Update an existing note (uses upsert for reliability)
  Future<int> updateNote(NotesCompanion note) {
    return into(notes).insertOnConflictUpdate(note);
  }

  /// Delete a note by ID
  Future<int> deleteNote(String id) {
    return (delete(notes)..where((note) => note.id.equals(id))).go();
  }

  /// Search notes by title or content
  Future<List<Note>> searchNotes(String query) {
    final searchQuery = '%$query%';
    return (select(notes)
          ..where((note) =>
              note.title.like(searchQuery) |
              note.documentJson.like(searchQuery))
          ..orderBy([
            (note) => OrderingTerm(
                expression: note.updatedAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Get notes by preacher ID
  Future<List<Note>> getNotesByPreacher(String preacherId) {
    return (select(notes)
          ..where((note) => note.preacherId.equals(preacherId))
          ..orderBy([
            (note) => OrderingTerm(
                expression: note.updatedAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Get notes by folder ID
  Future<List<Note>> getNotesByFolder(String? folderId) {
    if (folderId == null) {
      return (select(notes)
            ..where((note) => note.folderId.isNull())
            ..orderBy([
              (note) => OrderingTerm(
                  expression: note.updatedAt, mode: OrderingMode.desc)
            ]))
          .get();
    }
    return (select(notes)
          ..where((note) => note.folderId.equals(folderId))
          ..orderBy([
            (note) => OrderingTerm(
                expression: note.updatedAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Move specific notes to a target folder
  Future<int> moveNotes(List<String> noteIds, String targetFolderId) {
    return (update(notes)..where((note) => note.id.isIn(noteIds)))
        .write(NotesCompanion(
          folderId: Value(targetFolderId),
          updatedAt: Value(DateTime.now()),
        ));
  }

  /// Move all notes from a folder to another folder (or root if targetFolderId is null)
  Future<int> moveNotesFromFolder(String sourceFolderId, String? targetFolderId) {
    return (update(notes)..where((note) => note.folderId.equals(sourceFolderId)))
        .write(NotesCompanion(
          folderId: Value(targetFolderId),
          updatedAt: Value(DateTime.now()),
        ));
  }

  /// Delete all notes in a folder
  Future<int> deleteNotesInFolder(String folderId) {
    return (delete(notes)..where((note) => note.folderId.equals(folderId))).go();
  }

  /// Get count of notes in a folder
  Future<int> getNoteCountInFolder(String? folderId) async {
    final query = selectOnly(notes)..addColumns([notes.id.count()]);
    if (folderId == null) {
      query.where(notes.folderId.isNull());
    } else {
      query.where(notes.folderId.equals(folderId));
    }
    final result = await query.getSingle();
    return result.read(notes.id.count()) ?? 0;
  }
}
