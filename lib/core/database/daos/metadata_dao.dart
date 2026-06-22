import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/preachers_table.dart';
import '../tables/tags_table.dart';
import '../../testing/test_clock.dart';

part 'metadata_dao.g.dart';

/// Data Access Object for Metadata (Preachers and Tags)
/// Handles CRUD operations for preachers, tags, and note-tag relationships
@DriftAccessor(tables: [Preachers, Tags, NoteTags])
class MetadataDao extends DatabaseAccessor<AppDatabase> with _$MetadataDaoMixin {
  MetadataDao(super.db);

  // ==================== Preachers ====================

  /// Get all preachers ordered by name
  Future<List<Preacher>> getAllPreachers() {
    return (select(preachers)
          ..orderBy([(preacher) => OrderingTerm(expression: preacher.name)]))
        .get();
  }

  /// Get preacher by ID
  Future<Preacher?> getPreacherById(String id) {
    return (select(preachers)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Get preacher by name
  Future<Preacher?> getPreacherByName(String name) {
    return (select(preachers)..where((p) => p.name.equals(name))).getSingleOrNull();
  }

  /// Create a new preacher
  Future<int> createPreacher(PreachersCompanion preacher) {
    return into(preachers).insert(preacher);
  }

  /// Get or create preacher by name
  Future<Preacher> getOrCreatePreacher(String name) async {
    final existing = await getPreacherByName(name);
    if (existing != null) return existing;

    final uuid = _generateUuid();
    await createPreacher(
      PreachersCompanion.insert(
        id: uuid,
        name: name,
        createdAt: DateTime.now(),
      ),
    );

    return (await getPreacherById(uuid))!;
  }

  /// Delete preacher
  Future<int> deletePreacher(String id) {
    return (delete(preachers)..where((p) => p.id.equals(id))).go();
  }

  // ==================== Tags ====================

  /// Get all tags ordered by name
  Future<List<Tag>> getAllTags() {
    return (select(tags)
          ..orderBy([(tag) => OrderingTerm(expression: tag.name)]))
        .get();
  }

  /// Get tag by ID
  Future<Tag?> getTagById(String id) {
    return (select(tags)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Get tag by name
  Future<Tag?> getTagByName(String name) {
    return (select(tags)..where((t) => t.name.equals(name))).getSingleOrNull();
  }

  /// Create a new tag
  Future<int> createTag(TagsCompanion tag) {
    return into(tags).insert(tag);
  }

  /// Get or create tag by name
  Future<Tag> getOrCreateTag(String name) async {
    final existing = await getTagByName(name);
    if (existing != null) return existing;

    final uuid = _generateUuid();
    await createTag(
      TagsCompanion.insert(
        id: uuid,
        name: name,
        createdAt: DateTime.now(),
      ),
    );

    return (await getTagById(uuid))!;
  }

  /// Delete tag
  Future<int> deleteTag(String id) {
    return (delete(tags)..where((t) => t.id.equals(id))).go();
  }

  // ==================== Note-Tag Relationships ====================

  /// Get tags for a note
  Future<List<Tag>> getTagsForNote(String noteId) async {
    final query = select(noteTags).join([
      innerJoin(tags, tags.id.equalsExp(noteTags.tagId))
    ])
      ..where(noteTags.noteId.equals(noteId));

    final rows = await query.get();
    return rows.map((row) => row.readTable(tags)).toList();
  }

  /// Watch tags for a note (reactive stream)
  Stream<List<Tag>> watchTagsForNote(String noteId) {
    final query = select(noteTags).join([
      innerJoin(tags, tags.id.equalsExp(noteTags.tagId))
    ])
      ..where(noteTags.noteId.equals(noteId));

    return query.watch().map((rows) {
      return rows.map((row) => row.readTable(tags)).toList();
    });
  }

  /// Add tag to note
  Future<int> addTagToNote(String noteId, String tagId) {
    return into(noteTags).insert(
      NoteTagsCompanion.insert(
        noteId: noteId,
        tagId: tagId,
        createdAt: DateTime.now(),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Remove tag from note
  Future<int> removeTagFromNote(String noteId, String tagId) {
    return (delete(noteTags)
          ..where((nt) =>
              nt.noteId.equals(noteId) & nt.tagId.equals(tagId)))
        .go();
  }

  /// Set tags for a note (replaces all existing tags)
  Future<void> setTagsForNote(String noteId, List<String> tagIds) async {
    await transaction(() async {
      // Remove all existing tags
      await (delete(noteTags)..where((nt) => nt.noteId.equals(noteId))).go();

      // Add new tags
      for (final tagId in tagIds) {
        await addTagToNote(noteId, tagId);
      }
    });
  }

  /// Get notes with a specific tag
  Future<List<String>> getNoteIdsWithTag(String tagId) async {
    final query = select(noteTags)..where((nt) => nt.tagId.equals(tagId));
    final rows = await query.get();
    return rows.map((row) => row.noteId).toList();
  }

  // ==================== Utility ====================

  String _generateUuid() {
    return TestClock.now().toString();
  }
}
