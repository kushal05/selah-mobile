import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../features/notes/data/converters/note_block_converter.dart';
import '../../../features/notes/domain/models/editor_document.dart';
import '../../sync/repositories/note_block_repository.dart';
import '../../sync/repositories/note_repository.dart';
import '../../sync/repositories/note_tag_repository.dart';
import '../../sync/repositories/preacher_repository.dart';
import '../../sync/repositories/tag_repository.dart';
import '../app_database.dart';

const _kMigrationFlag = 'notes_migrated_to_sync';

/// One-time migration service that copies data from the old [AppDatabase]
/// (no sync/oplog) into the sync-enabled repositories so that existing
/// notes, preachers, tags, and note-tag relations start producing oplog
/// entries and can sync to MongoDB.
class NotesMigrationService {
  final AppDatabase _oldDb;
  final NoteRepository _noteRepo;
  final NoteBlockRepository _blockRepo;
  final PreacherRepository _preacherRepo;
  final TagRepository _tagRepo;
  final NoteTagRepository _noteTagRepo;
  final SharedPreferences _prefs;
  final String _userId;

  NotesMigrationService({
    required AppDatabase oldDb,
    required NoteRepository noteRepo,
    required NoteBlockRepository blockRepo,
    required PreacherRepository preacherRepo,
    required TagRepository tagRepo,
    required NoteTagRepository noteTagRepo,
    required SharedPreferences prefs,
    required String userId,
  })  : _oldDb = oldDb,
        _noteRepo = noteRepo,
        _blockRepo = blockRepo,
        _preacherRepo = preacherRepo,
        _tagRepo = tagRepo,
        _noteTagRepo = noteTagRepo,
        _prefs = prefs,
        _userId = userId;

  /// Returns true if migration has already been completed.
  bool get isMigrated => _prefs.getBool(_kMigrationFlag) ?? false;

  /// Run the migration. Safe to call multiple times — will no-op if already done.
  Future<void> migrate() async {
    if (isMigrated) return;

    developer.log('NotesMigration: Starting migration from AppDatabase → SyncDatabase');

    try {
      // Maps from old ID → new sync ID (in case IDs need remapping)
      // We preserve original IDs where possible.
      final preacherIdMap = <String, String>{}; // oldId → syncId
      final tagIdMap = <String, String>{}; // oldId → syncId

      // 1. Migrate preachers
      final oldPreachers = await _oldDb.metadataDao.getAllPreachers();
      developer.log('NotesMigration: Migrating ${oldPreachers.length} preachers');
      for (final oldPreacher in oldPreachers) {
        // Check if already exists (by name) to avoid duplicates
        final existing = await _preacherRepo.getPreacherByName(
          oldPreacher.name,
          _userId,
        );
        if (existing != null) {
          preacherIdMap[oldPreacher.id] = existing.id;
        } else {
          final created = await _preacherRepo.createPreacher(
            userId: _userId,
            name: oldPreacher.name,
          );
          preacherIdMap[oldPreacher.id] = created.id;
        }
      }

      // 2. Migrate tags
      final oldTags = await _oldDb.metadataDao.getAllTags();
      developer.log('NotesMigration: Migrating ${oldTags.length} tags');
      for (final oldTag in oldTags) {
        final existing = await _tagRepo.getTagByName(oldTag.name, _userId);
        if (existing != null) {
          tagIdMap[oldTag.id] = existing.id;
        } else {
          final created = await _tagRepo.createTag(
            userId: _userId,
            name: oldTag.name,
          );
          tagIdMap[oldTag.id] = created.id;
        }
      }

      // 3. Migrate notes + blocks
      final oldNotes = await _oldDb.notesDao.getAllNotes();
      developer.log('NotesMigration: Migrating ${oldNotes.length} notes');
      for (final oldNote in oldNotes) {
        try {
          // Check if note already exists in sync DB (by ID)
          final existingNote = await _noteRepo.getNoteById(oldNote.id);
          if (existingNote != null) {
            developer.log('NotesMigration: Skipping note ${oldNote.id} (already exists)');
            continue;
          }

          // Map preacher ID to new sync ID
          final syncPreacherId = oldNote.preacherId != null
              ? preacherIdMap[oldNote.preacherId]
              : null;

          // Create note in sync DB
          await _noteRepo.createNote(
            id: oldNote.id,
            folderId: oldNote.folderId ?? 'root',
            userId: _userId,
            title: oldNote.title,
            preacherId: syncPreacherId,
            noteDate: oldNote.noteDate?.millisecondsSinceEpoch,
          );

          // Parse document JSON → EditorDocument → NoteBlockModels
          final docJson = jsonDecode(oldNote.documentJson) as Map<String, dynamic>;
          final document = EditorDocument.fromJson(docJson);
          final blockData = NoteBlockConverter.fromEditorDocument(document);

          if (blockData.isNotEmpty) {
            final requests = blockData
                .map((b) => BlockCreateRequest(
                      blockType: b.blockType,
                      content: b.content,
                      orderIndex: b.orderIndex,
                    ))
                .toList();
            await _blockRepo.createBlocks(oldNote.id, requests);
          }

          // 4. Migrate note-tag relationships for this note
          final oldTagsForNote = await _oldDb.metadataDao.getTagsForNote(oldNote.id);
          for (final oldTag in oldTagsForNote) {
            final syncTagId = tagIdMap[oldTag.id];
            if (syncTagId != null) {
              await _noteTagRepo.addTagToNote(
                noteId: oldNote.id,
                tagId: syncTagId,
                userId: _userId,
              );
            }
          }
        } catch (e, stack) {
          developer.log(
            'NotesMigration: Failed to migrate note ${oldNote.id}, skipping',
            error: e,
            stackTrace: stack,
          );
          continue;
        }
      }

      // Mark migration as complete
      await _prefs.setBool(_kMigrationFlag, true);
      developer.log('NotesMigration: Migration complete');
    } catch (e, stack) {
      developer.log(
        'NotesMigration: Migration failed',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }
}
