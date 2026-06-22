import '../models/note.dart';

/// Abstract repository interface for notes
/// Defines the contract for note persistence operations
abstract class NotesRepository {
  /// Get all notes
  Future<List<Note>> getAllNotes();

  /// Get a note by ID
  Future<Note?> getNoteById(String id);

  /// Watch a note by ID (reactive stream)
  Stream<Note?> watchNoteById(String id);

  /// Watch all notes (reactive stream)
  Stream<List<Note>> watchAllNotes();

  /// Create a new note
  Future<void> createNote(Note note);

  /// Update an existing note
  Future<void> updateNote(Note note);

  /// Toggle the checked state of a checkbox block without rewriting the full document.
  Future<void> toggleCheckboxBlock(String noteId, String blockId);

  /// Delete a note
  Future<void> deleteNote(String id);

  /// Search notes by query
  Future<List<Note>> searchNotes(String query);

  /// Get notes by preacher ID
  Future<List<Note>> getNotesByPreacher(String preacherId);

  /// Get notes with specific tag
  Future<List<Note>> getNotesWithTag(String tagId);

  /// Get tags for a note
  Future<List<String>> getTagsForNote(String noteId);

  /// Set tags for a note (replaces all existing tags)
  Future<void> setTagsForNote(String noteId, List<String> tagIds);

  /// Add tag to note
  Future<void> addTagToNote(String noteId, String tagId);

  /// Remove tag from note
  Future<void> removeTagFromNote(String noteId, String tagId);

  /// Get notes in a specific folder (null for root level)
  Future<List<Note>> getNotesByFolder(String? folderId);

  /// Move specific notes to a target folder. Returns the number of notes moved.
  Future<int> moveNotes(List<String> noteIds, String targetFolderId);

  /// Move all notes from a folder to another folder (or root if targetFolderId is null)
  Future<void> moveNotesFromFolder(String sourceFolderId, String? targetFolderId);

  /// Delete all notes in a folder
  Future<void> deleteNotesInFolder(String folderId);

  /// Get count of notes in a folder
  Future<int> getNoteCountInFolder(String? folderId);

  /// Move a note to the trash (recoverable)
  Future<void> trashNote(String id);

  /// Restore a note from the trash
  Future<void> restoreNote(String id);
}
