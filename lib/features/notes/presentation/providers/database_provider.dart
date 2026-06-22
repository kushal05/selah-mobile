import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/models/note_block_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../data/repositories/note_revision_repository.dart';
import '../../data/repositories/sync_notes_repository_adapter.dart';
import '../../data/services/note_backlinks_service.dart';
import '../../data/services/note_restore_service.dart';
import '../../domain/models/note.dart' as domain;
import '../../domain/models/note_revision.dart';
import '../../domain/repositories/notes_repository.dart';

/// Provider for the note revision repository (local-only, not synced).
final noteRevisionRepositoryProvider =
    Provider<NoteRevisionRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  return NoteRevisionRepository(database);
});

/// Provider for the notes repository, backed by the sync-enabled database.
///
/// All mutations create oplog entries for server synchronization.
final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  final noteRepo = ref.watch(noteRepositoryProvider);
  final blockRepo = ref.watch(noteBlockRepositoryProvider);
  final noteTagRepo = ref.watch(noteTagRepositoryProvider);
  final revisionRepo = ref.watch(noteRevisionRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return SyncNotesRepositoryAdapter(
    noteRepo: noteRepo,
    blockRepo: blockRepo,
    noteTagRepo: noteTagRepo,
    revisionRepo: revisionRepo,
    userId: userId,
  );
});

/// Stream provider for all notes from the sync database.
final notesStreamProvider = StreamProvider<List<domain.Note>>((ref) {
  final repository = ref.watch(notesRepositoryProvider);
  return repository.watchAllNotes();
});

/// Provider for note count in a specific folder.
/// Pass null to get count of notes at root level.
final noteCountInFolderProvider =
    FutureProvider.family<int, String?>((ref, folderId) async {
  final repository = ref.watch(notesRepositoryProvider);
  return repository.getNoteCountInFolder(folderId);
});

/// Watch all revisions for a note, newest first.
final noteRevisionsProvider =
    StreamProvider.family<List<NoteRevisionSnapshot>, String>(
        (ref, noteId) {
  final revisionRepo = ref.watch(noteRevisionRepositoryProvider);
  return revisionRepo.watchRevisions(noteId);
});

/// Get a single revision by ID.
final noteRevisionProvider =
    FutureProvider.family<NoteRevisionSnapshot?, String>(
        (ref, revisionId) async {
  final revisionRepo = ref.watch(noteRevisionRepositoryProvider);
  return revisionRepo.getRevision(revisionId);
});

/// Provider for the note restore service.
final noteRestoreServiceProvider = Provider<NoteRestoreService>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  final noteRepo = ref.watch(noteRepositoryProvider);
  final blockRepo = ref.watch(noteBlockRepositoryProvider);
  final revisionRepo = ref.watch(noteRevisionRepositoryProvider);
  return NoteRestoreService(
    db: db,
    noteRepo: noteRepo,
    blockRepo: blockRepo,
    revisionRepo: revisionRepo,
  );
});

/// Loads current (non-deleted) note blocks for a given note ID, ordered by
/// sort index. Used by the revision diff view to compare against a snapshot.
final currentNoteBlocksProvider =
    FutureProvider.family<List<NoteBlockModel>, String>(
        (ref, noteId) async {
  final blockRepo = ref.watch(noteBlockRepositoryProvider);
  return blockRepo.getBlocksForNote(noteId);
});

/// Service for finding notes that reference the current note. See
/// [NoteBacklinksService] for the matching strategy (title phrase + wiki-link).
final noteBacklinksServiceProvider = Provider<NoteBacklinksService>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  final fts = ref.watch(noteBlockFtsServiceProvider);
  return NoteBacklinksService(db, fts);
});

/// Backlinks for a given note. Invalidate on note edits to refresh.
final noteBacklinksProvider =
    FutureProvider.family<List<Backlink>, String>((ref, noteId) async {
  final service = ref.watch(noteBacklinksServiceProvider);
  final userId = ref.watch(currentUserIdProvider);
  return service.findBacklinks(noteId: noteId, userId: userId);
});
