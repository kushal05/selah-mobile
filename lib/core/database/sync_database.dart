import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/folders_table.dart';
import 'tables/sync_notes_table.dart';
import 'tables/note_blocks_table.dart';
import 'tables/oplog_table.dart';
import 'tables/sync_state_table.dart';
import 'tables/devices_table.dart';
import 'tables/prayers_table.dart';
import 'tables/promises_table.dart';
import 'tables/people_table.dart';
import 'tables/songs_table.dart';
import 'tables/prayer_logs_table.dart';
import 'tables/bible_cache_table.dart';
import 'tables/user_profiles_table.dart';
import 'tables/friendships_table.dart';
import 'tables/friend_requests_table.dart';
import 'tables/blocked_users_table.dart';
import 'tables/shared_prayers_table.dart';
import 'tables/prayer_collaborators_table.dart';
import 'tables/groups_table.dart';
import 'tables/group_members_table.dart';
import 'tables/group_prayers_table.dart';
import 'tables/group_announcements_table.dart';
import 'tables/sync_preachers_table.dart';
import 'tables/sync_tags_table.dart';
import 'tables/sync_note_tags_table.dart';
import 'tables/prayer_updates_table.dart';
import 'tables/promise_conditions_table.dart';
import 'tables/sync_promise_tags_table.dart';
import 'tables/sync_prayer_tags_table.dart';
import 'tables/sync_prayer_people_table.dart';
import 'tables/sync_song_tags_table.dart';
import 'tables/pending_group_members_table.dart';
import 'tables/note_revisions_table.dart';
import 'tables/promise_prayer_links_table.dart';
import 'tables/bible_highlights_table.dart';
import 'tables/entity_access_table.dart';
import 'tables/document_operations_table.dart';
import 'tables/share_codes_table.dart';
import 'tables/feedback_threads_table.dart';
import 'tables/feedback_messages_table.dart';
import 'tables/feedback_attachments_table.dart';
import 'tables/bible_reference_history_table.dart';
import 'tables/bible_bookmarks_table.dart';
import 'tables/habit_logs_table.dart';
import 'tables/bible_version_states_table.dart';
import 'services/note_block_fts_service.dart';
import '../config/app_config.dart';
import '../testing/test_clock.dart';

part 'sync_database.g.dart';

/// Sync-enabled database for offline-first architecture
///
/// Per spec section 3.1 Core Design Rules:
/// 1. Every table has: id, updatedAt, version, deleted
/// 2. No cascading deletes
/// 3. No hard deletes
/// 4. All writes are transactional
///
/// This database is the SINGLE SOURCE OF TRUTH.
/// MongoDB is an eventually consistent replica.
@DriftDatabase(
  tables: [
    Folders,
    SyncNotes,
    NoteBlocks,
    Oplog,
    SyncState,
    Devices,
    Prayers,
    Promises,
    People,
    Songs,
    // v4 tables
    PrayerLogs,
    BibleCache,
    UserProfiles,
    Friendships,
    FriendRequests,
    BlockedUsers,
    SharedPrayers,
    PrayerCollaborators,
    Groups,
    GroupMembers,
    GroupPrayers,
    GroupAnnouncements,
    // v5 tables
    SyncPreachers,
    SyncTags,
    SyncNoteTags,
    // v9 tables
    PrayerUpdates,
    // v10 tables
    PromiseConditions,
    SyncPromiseTags,
    SyncPrayerTags,
    SyncPrayerPeople,
    // v12 tables
    SyncSongTags,
    // v13 tables
    PendingGroupMembers,
    // v16 tables (local-only, not synced)
    NoteRevisions,
    // v17 tables
    PromisePrayerLinks,
    // v19 tables (local-only, not synced)
    BibleHighlights,
    // v21 tables — ACL + CRDT foundation
    EntityAccess,
    DocumentOperations,
    ShareCodes,
    // v22 tables — User feedback system
    FeedbackThreads,
    FeedbackMessages,
    // v23 tables — Feedback attachments + expanded thread/message fields
    FeedbackAttachments,
    // v24 tables — Bible reference history tracking
    BibleReferenceHistory,
    // v26 tables — Bible bookmarks (local-only)
    BibleBookmarks,
    // v27/v30 tables — Habit logs (synced from v30)
    HabitLogs,
    // v29 tables — Bible version state registry (local-only)
    BibleVersionStates,
  ],
)
class SyncDatabase extends _$SyncDatabase {
  SyncDatabase() : super(_openConnection());

  /// Named constructor for testing with custom executor
  SyncDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 33;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();

          // Initialize sync_state with single row
          await into(syncState).insert(
            SyncStateCompanion.insert(
              id: const Value(1),
              syncStatus: const Value(SyncStatus.idle),
            ),
          );

          // FTS5 virtual table for note block full-text search (not managed by Drift)
          await customStatement(
            "CREATE VIRTUAL TABLE IF NOT EXISTS note_blocks_fts "
            "USING fts5(plain_text, note_id UNINDEXED, block_id UNINDEXED)",
          );

          // Raw SQL indexes not managed by Drift — must be created in both
          // onCreate (fresh installs) and the corresponding onUpgrade block.
          // Partial unique index: one active check-in per (user, habit, day).
          // WHERE deleted = 0 allows re-insertion after a soft delete from another device.
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_habit_logs_unique '
            'ON habit_logs(user_id, habit_type, date_day) WHERE deleted = 0',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_bible_bookmarks_unique '
            'ON bible_bookmarks(user_id, book_id, chapter)',
          );
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Migration strategy per spec section 10:
          // - Local migration first
          // - Remote ops versioned
          //
          // Each migration step should:
          // 1. Add new columns with defaults
          // 2. Never remove columns in the same version
          // 3. Mark schema version in oplog for remote handling

          if (from < 2) {
            // Add songs table
            await m.createTable(songs);
          }

          if (from < 3) {
            // Add user_id column to prayers, promises, people, songs
            await customStatement(
              "ALTER TABLE prayers ADD COLUMN user_id TEXT NOT NULL DEFAULT 'default-user-id'",
            );
            await customStatement(
              "ALTER TABLE promises ADD COLUMN user_id TEXT NOT NULL DEFAULT 'default-user-id'",
            );
            await customStatement(
              "ALTER TABLE people ADD COLUMN user_id TEXT NOT NULL DEFAULT 'default-user-id'",
            );
            // Songs table may already have user_id if created fresh at v3
            // For users upgrading from v2, add the column
            await customStatement(
              "ALTER TABLE songs ADD COLUMN user_id TEXT NOT NULL DEFAULT 'default-user-id'",
            );
          }

          if (from < 4) {
            // Feature 2: Pray Today
            await m.createTable(prayerLogs);
            // Feature 1: Bible References (local cache only)
            await m.createTable(bibleCache);
            // Feature 4: Friends
            await m.createTable(userProfiles);
            await m.createTable(friendships);
            await m.createTable(friendRequests);
            await m.createTable(blockedUsers);
            // Feature 3: Shared Prayers
            await m.createTable(sharedPrayers);
            await m.createTable(prayerCollaborators);
            // Feature 5: Groups
            await m.createTable(groups);
            await m.createTable(groupMembers);
            await m.createTable(groupPrayers);
            await m.createTable(groupAnnouncements);
          }

          if (from < 5) {
            // Sync-enabled preachers, tags, and note-tags
            await m.createTable(syncPreachers);
            await m.createTable(syncTags);
            await m.createTable(syncNoteTags);
          }

          if (from < 6) {
            // Song enhancements: structured chord lines + musical key.
            // Guard: if the songs table was freshly created at v2+ via
            // m.createTable (which uses the current schema), these columns
            // already exist. Only ALTER for databases where the table
            // predates v6.
            final songCols = await customSelect(
              "PRAGMA table_info(songs)",
            ).get();
            final colNames = songCols.map((r) => r.read<String>('name')).toSet();

            if (!colNames.contains('scale')) {
              await customStatement(
                "ALTER TABLE songs ADD COLUMN scale TEXT NOT NULL DEFAULT ''",
              );
            }
            if (!colNames.contains('chord_lines')) {
              await customStatement(
                "ALTER TABLE songs ADD COLUMN chord_lines TEXT NOT NULL DEFAULT ''",
              );
            }
          }

          if (from < 7) {
            // Add type column to folders for separating song/note folders.
            final folderCols = await customSelect(
              "PRAGMA table_info(folders)",
            ).get();
            final colNames = folderCols.map((r) => r.read<String>('name')).toSet();

            if (!colNames.contains('type')) {
              await customStatement(
                "ALTER TABLE folders ADD COLUMN type TEXT NOT NULL DEFAULT 'note'",
              );
            }
          }

          if (from < 8) {
            // Ensure user profile editable fields exist for older/partial schemas.
            await _ensureUserProfileColumns();
          }

          if (from < 9) {
            // Prayer updates as structured records + new columns on existing tables.
            await m.createTable(prayerUpdates);

            // Add reminder_at column to prayers (was previously in category metadata).
            final prayerCols = await customSelect(
              "PRAGMA table_info(prayers)",
            ).get();
            final prayerColNames =
                prayerCols.map((r) => r.read<String>('name')).toSet();
            if (!prayerColNames.contains('reminder_at')) {
              await customStatement(
                "ALTER TABLE prayers ADD COLUMN reminder_at INTEGER",
              );
            }

            // Add join_policy column to groups.
            final groupCols = await customSelect(
              "PRAGMA table_info(groups)",
            ).get();
            final groupColNames =
                groupCols.map((r) => r.read<String>('name')).toSet();
            if (!groupColNames.contains('join_policy')) {
              await customStatement(
                "ALTER TABLE groups ADD COLUMN join_policy TEXT NOT NULL DEFAULT 'codeOnly'",
              );
            }
          }

          if (from < 10) {
            // Structured promise conditions, promise-tag, prayer-tag,
            // and prayer-people junction tables.
            await m.createTable(promiseConditions);
            await m.createTable(syncPromiseTags);
            await m.createTable(syncPrayerTags);
            await m.createTable(syncPrayerPeople);
          }

          if (from < 11) {
            // Add visibility and group_id columns to folders.

            final folderCols = await customSelect(
              "PRAGMA table_info(folders)",
            ).get();
            final colNames =
                folderCols.map((r) => r.read<String>('name')).toSet();

            if (!colNames.contains('visibility')) {
              await customStatement(
                "ALTER TABLE folders ADD COLUMN visibility TEXT NOT NULL DEFAULT 'personal'",
              );
            }
            if (!colNames.contains('group_id')) {
              await customStatement(
                "ALTER TABLE folders ADD COLUMN group_id TEXT",
              );
            }
          }

          if (from < 12) {
            // Song-tag junction table for global tags.
            await m.createTable(syncSongTags);

            // Migrate existing comma-separated song tags to junction table.
            await _migrateSongTagsToJunction();
          }

          if (from < 13) {
            // Pending group membership requests table (approval join policy).
            await m.createTable(pendingGroupMembers);
          }

          if (from < 14) {
            // Add section column to note_blocks for Personal Application / Prayer sections.
            final blockCols = await customSelect(
              "PRAGMA table_info(note_blocks)",
            ).get();
            final colNames = blockCols.map((r) => r.read<String>('name')).toSet();

            if (!colNames.contains('section')) {
              await customStatement(
                "ALTER TABLE note_blocks ADD COLUMN section TEXT NOT NULL DEFAULT 'main'",
              );
            }
          }

          if (from < 15) {
            // B1 fix: Add failure tracking columns to oplog so permanently
            // failing operations can be quarantined instead of blocking the
            // entire push queue.
            final oplogCols = await customSelect(
              "PRAGMA table_info(oplog)",
            ).get();
            final colNames =
                oplogCols.map((r) => r.read<String>('name')).toSet();

            if (!colNames.contains('failed_at')) {
              await customStatement(
                "ALTER TABLE oplog ADD COLUMN failed_at INTEGER",
              );
            }
            if (!colNames.contains('failed_reason')) {
              await customStatement(
                "ALTER TABLE oplog ADD COLUMN failed_reason TEXT",
              );
            }
          }

          if (from < 16) {
            // Note revision snapshots (local-only, not synced).
            await m.createTable(noteRevisions);
          }

          if (from < 17) {
            // Promise-Prayer bidirectional linking junction table.
            await m.createTable(promisePrayerLinks);
          }

          if (from < 18) {
            // Field-level merge: add fieldUpdatedAt to sync entities.
            await customStatement(
              "ALTER TABLE sync_notes ADD COLUMN field_updated_at TEXT NOT NULL DEFAULT '{}'",
            );
            await customStatement(
              "ALTER TABLE prayers ADD COLUMN field_updated_at TEXT NOT NULL DEFAULT '{}'",
            );
            await customStatement(
              "ALTER TABLE user_profiles ADD COLUMN field_updated_at TEXT NOT NULL DEFAULT '{}'",
            );
            await customStatement(
              "ALTER TABLE groups ADD COLUMN field_updated_at TEXT NOT NULL DEFAULT '{}'",
            );

            // Hybrid note model: add documentJson snapshot column.
            await customStatement(
              "ALTER TABLE sync_notes ADD COLUMN document_json TEXT",
            );

            // Backfill documentJson from existing note blocks.
            await _backfillDocumentJson();
          }

          if (from < 19) {
            // Bible verse highlights (local-only, not synced).
            await m.createTable(bibleHighlights);
          }

          if (from < 20) {
            // FTS5 virtual table for note block full-text search.
            await customStatement(
              "CREATE VIRTUAL TABLE IF NOT EXISTS note_blocks_fts "
              "USING fts5(plain_text, note_id UNINDEXED, block_id UNINDEXED)",
            );

            // Backfill FTS index from existing non-deleted blocks.
            await _backfillNoteBlocksFts();
          }

          if (from < 21) {
            // v21: Universal ACL + CRDT foundation tables.

            // 1. entity_access — universal access control
            await m.createTable(entityAccess);

            // 2. document_operations — CRDT editing operations (local-only)
            await m.createTable(documentOperations);

            // 3. share_codes — local lookup for share code → entity_access
            await m.createTable(shareCodes);

            // 4. Indexes for entity_access
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_entity_access_entity
              ON entity_access(entity_id, access_type) WHERE deleted = 0
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_entity_access_user_type
              ON entity_access(user_id, entity_type) WHERE deleted = 0
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_entity_access_target
              ON entity_access(target_id, access_type) WHERE deleted = 0
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_entity_access_updated
              ON entity_access(updated_at)
            ''');

            // 5. Indexes for document_operations
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_doc_ops_entity
              ON document_operations(entity_id, sequence_number)
            ''');

            // 6. Data migration: create owner access records for all existing entities.
            await _migrateOwnerAccessRecords();

            // 7. Data migration: migrate SharedPrayers → entity_access.
            await _migrateSharedPrayersToEntityAccess();

            // 8. Data migration: migrate PrayerCollaborators → entity_access.
            await _migratePrayerCollaboratorsToEntityAccess();
          }

          if (from < 22) {
            // v22: User feedback system.
            await m.createTable(feedbackThreads);
            await m.createTable(feedbackMessages);

            // Indexes for efficient lookups
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_feedback_threads_user
              ON feedback_threads(user_id) WHERE deleted = 0
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_feedback_messages_thread
              ON feedback_messages(thread_id) WHERE deleted = 0
            ''');
          }

          if (from < 23) {
            // v23: Feedback attachments table + expanded thread/message fields.
            await m.createTable(feedbackAttachments);

            // New columns on feedback_threads (all nullable with defaults).
            await customStatement(
                "ALTER TABLE feedback_threads ADD COLUMN priority TEXT NOT NULL DEFAULT 'medium'");
            await customStatement(
                'ALTER TABLE feedback_threads ADD COLUMN unread_for_user INTEGER NOT NULL DEFAULT 0');
            await customStatement(
                'ALTER TABLE feedback_threads ADD COLUMN unread_for_admin INTEGER NOT NULL DEFAULT 0');
            await customStatement(
                'ALTER TABLE feedback_threads ADD COLUMN device_model TEXT');
            await customStatement(
                'ALTER TABLE feedback_threads ADD COLUMN os_version TEXT');
            await customStatement(
                'ALTER TABLE feedback_threads ADD COLUMN app_version TEXT');

            // New column on feedback_messages.
            await customStatement(
                'ALTER TABLE feedback_messages ADD COLUMN has_attachments INTEGER NOT NULL DEFAULT 0');

            // Indexes for attachments and thread status.
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_feedback_attachments_message
              ON feedback_attachments(message_id) WHERE deleted = 0
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_feedback_threads_status
              ON feedback_threads(status) WHERE deleted = 0
            ''');
          }

          if (from < 24) {
            // v24: Bible reference history tracking (synced).
            await m.createTable(bibleReferenceHistory);

            // Indexes for efficient history queries.
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_bible_history_user_time
              ON bible_reference_history(user_id, opened_at DESC)
              WHERE deleted = 0
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_bible_history_book
              ON bible_reference_history(book, chapter)
            ''');
          }

          if (from < 25) {
            // v25: Add trashed_at column for bin/trash feature.
            // Trashed items have deleted=0 + trashed_at set (recoverable).
            // Permanent delete sets deleted=1 (existing flow).
            const tables = [
              'sync_notes', 'folders', 'prayers', 'promises',
              'people', 'songs', 'sync_preachers', 'sync_tags',
              'note_blocks', 'sync_note_tags', 'sync_prayer_tags',
              'sync_prayer_people', 'prayer_updates', 'prayer_logs',
              'sync_promise_tags', 'promise_conditions',
              'promise_prayer_links', 'sync_song_tags',
            ];
            for (final table in tables) {
              await customStatement(
                'ALTER TABLE $table ADD COLUMN trashed_at INTEGER',
              );
            }
          }

          if (from < 26) {
            // v26a: Add sync fields to bible_highlights so they survive
            // device changes. Flutter-only entity type (bibleHighlight)
            // pending Worker support — same pattern as feedbackThread.
            final highlightCols = await customSelect(
              'PRAGMA table_info(bible_highlights)',
            ).get();
            final hColNames =
                highlightCols.map((r) => r.read<String>('name')).toSet();
            if (!hColNames.contains('user_id')) {
              await customStatement(
                "ALTER TABLE bible_highlights ADD COLUMN user_id TEXT NOT NULL DEFAULT ''",
              );
            }
            if (!hColNames.contains('version')) {
              await customStatement(
                'ALTER TABLE bible_highlights ADD COLUMN version INTEGER NOT NULL DEFAULT 1',
              );
            }
            if (!hColNames.contains('deleted')) {
              await customStatement(
                'ALTER TABLE bible_highlights ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
              );
            }

            // v26b: Bible bookmarks (local-only — no sync).
            await customStatement('''
              CREATE TABLE IF NOT EXISTS bible_bookmarks (
                id TEXT NOT NULL PRIMARY KEY,
                user_id TEXT NOT NULL,
                book_id INTEGER NOT NULL,
                book_name TEXT NOT NULL,
                chapter INTEGER NOT NULL,
                translation TEXT NOT NULL,
                created_at INTEGER NOT NULL
              )
            ''');
            await customStatement('''
              CREATE INDEX IF NOT EXISTS idx_bible_bookmarks_user
              ON bible_bookmarks(user_id, created_at DESC)
            ''');
          }

          if (from < 27) {
            // v27: Daily habit check-in logs (local-only — no sync).
            await customStatement('''
              CREATE TABLE IF NOT EXISTS habit_logs (
                id TEXT NOT NULL PRIMARY KEY,
                user_id TEXT NOT NULL,
                habit_type TEXT NOT NULL CHECK(habit_type IN ('bible', 'meditation', 'journal')),
                date_day INTEGER NOT NULL,
                created_at INTEGER NOT NULL
              )
            ''');
            await customStatement('''
              CREATE UNIQUE INDEX IF NOT EXISTS idx_habit_logs_unique
              ON habit_logs(user_id, habit_type, date_day)
            ''');
          }

          if (from < 28) {
            // v28: Add UNIQUE constraint on bible_bookmarks(user_id, book_id, chapter)
            // to prevent duplicate bookmarks from rapid double-taps.
            // Deduplicate first — keep one arbitrary row per (user, book, chapter)
            // in case any duplicates slipped through before this constraint existed.
            // MIN(id) on UUID strings is lexicographic, not chronological, but the
            // outcome is the same: exactly one row per group survives.
            await customStatement('''
              DELETE FROM bible_bookmarks
              WHERE id NOT IN (
                SELECT MIN(id) FROM bible_bookmarks
                GROUP BY user_id, book_id, chapter
              )
            ''');
            await customStatement('''
              CREATE UNIQUE INDEX IF NOT EXISTS idx_bible_bookmarks_unique
              ON bible_bookmarks(user_id, book_id, chapter)
            ''');
          }

          if (from < 29) {
            // v29: Bible version state registry.
            // Stores available translations fetched from the server,
            // plus the user's chosen default. Local-only, never synced.
            await m.createTable(bibleVersionStates);
          }

          if (from < 30) {
            // v30: Add sync fields to habit_logs so check-ins replicate across
            // devices. Existing rows get default values — updatedAt from createdAt.
            await customStatement(
              'ALTER TABLE habit_logs ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE habit_logs ADD COLUMN version INTEGER NOT NULL DEFAULT 1',
            );
            await customStatement(
              'ALTER TABLE habit_logs ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE habit_logs ADD COLUMN trashed_at INTEGER',
            );

            // Backfill updated_at from created_at for pre-sync rows.
            await customStatement(
              'UPDATE habit_logs SET updated_at = created_at WHERE updated_at = 0',
            );

            // Drop the old unconditional unique index and replace it with a
            // partial one so that a re-insert after a remote soft-delete succeeds.
            await customStatement(
              'DROP INDEX IF EXISTS idx_habit_logs_unique',
            );
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_habit_logs_unique '
              'ON habit_logs(user_id, habit_type, date_day) WHERE deleted = 0',
            );
          }

          if (from < 31) {
            // v31: Add notes column to songs for free-form notes/references.
            await customStatement(
              "ALTER TABLE songs ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
            );
          }

          if (from < 32) {
            // v32: Explicit accept state for entity_access shares.
            // Owner/friend/group/public grants backfill to createdAt so the
            // permission gate still treats them as active. New tier-2 'user'
            // grants insert with NULL until the recipient accepts.
            final accessCols = await customSelect(
              'PRAGMA table_info(entity_access)',
            ).get();
            final accessColNames =
                accessCols.map((r) => r.read<String>('name')).toSet();
            if (!accessColNames.contains('accepted_at')) {
              await customStatement(
                'ALTER TABLE entity_access ADD COLUMN accepted_at INTEGER',
              );
              await customStatement(
                'UPDATE entity_access SET accepted_at = created_at '
                "WHERE access_type != 'user' AND accepted_at IS NULL",
              );
            }
          }

          if (from < 33) {
            // v33: Rebuild the note block FTS index.
            //
            // Bible reference blocks keep their JSON payload in content['text'],
            // and the index stored that JSON verbatim — so searches matched
            // internal keys ("insertedAt", "pending") and the verse text was
            // buried. extractPlainText now unwraps them, but existing rows hold
            // the old text, so re-index everything. Cheap and idempotent: the
            // index is a derived copy that can always be rebuilt from blocks.
            await customStatement('DELETE FROM note_blocks_fts');
            await _backfillNoteBlocksFts();
          }
        },
        beforeOpen: (details) async {
          // Ensure sync_state row exists
          final stateExists = await (select(syncState)
                ..where((s) => s.id.equals(1)))
              .getSingleOrNull();

          if (stateExists == null) {
            await into(syncState).insert(
              SyncStateCompanion.insert(
                id: const Value(1),
                syncStatus: const Value(SyncStatus.idle),
              ),
            );
          }

          // Defensive: keep user_profiles schema aligned even on edge-case installs.
          await _ensureUserProfileColumns();
        },
      );

  /// One-time migration: convert comma-separated song tags into
  /// the sync_song_tags junction table, reusing existing global tags.
  Future<void> _migrateSongTagsToJunction() async {
    final rows = await customSelect(
      "SELECT id, user_id, tags FROM songs WHERE deleted = 0 AND tags != ''",
    ).get();

    final now = TestClock.now();

    for (final row in rows) {
      final songId = row.read<String>('id');
      final userId = row.read<String>('user_id');
      final rawTags = row.read<String>('tags');

      for (final part in rawTags.split(',')) {
        final tagName = part.trim();
        if (tagName.isEmpty) continue;

        // Find or create the global tag
        final existing = await customSelect(
          "SELECT id FROM sync_tags WHERE name = ? AND user_id = ? AND deleted = 0",
          variables: [Variable.withString(tagName), Variable.withString(userId)],
        ).getSingleOrNull();

        String tagId;
        if (existing != null) {
          tagId = existing.read<String>('id');
        } else {
          tagId = '${now.toRadixString(16)}-${tagName.hashCode.toRadixString(16)}';
          await customStatement(
            "INSERT INTO sync_tags (id, user_id, name, updated_at, version, deleted, created_at) "
            "VALUES (?, ?, ?, ?, 1, 0, ?)",
            [tagId, userId, tagName, now, now],
          );
        }

        // Create junction row
        final junctionId = '${songId.hashCode.toRadixString(16)}-${tagId.hashCode.toRadixString(16)}';
        await customStatement(
          "INSERT OR IGNORE INTO sync_song_tags (id, song_id, tag_id, user_id, updated_at, version, deleted, created_at) "
          "VALUES (?, ?, ?, ?, ?, 1, 0, ?)",
          [junctionId, songId, tagId, userId, now, now],
        );
      }
    }
  }

  /// One-time migration: build documentJson from existing note blocks.
  Future<void> _backfillDocumentJson() async {
    final notes = await customSelect(
      'SELECT id FROM sync_notes WHERE deleted = 0',
    ).get();

    for (final row in notes) {
      final noteId = row.read<String>('id');
      final blocks = await customSelect(
        'SELECT id, note_id, block_type, content_json, order_index, '
        'updated_at, version, deleted, created_at, section '
        'FROM note_blocks WHERE note_id = ? AND deleted = 0 ORDER BY order_index',
        variables: [Variable.withString(noteId)],
      ).get();

      if (blocks.isEmpty) continue;

      final blockJsonList = blocks.map((b) {
        // Decode content_json so it embeds as a nested object (not a string),
        // matching the format produced by NoteBlockModel.toJson().
        Map<String, dynamic> content;
        try {
          content = jsonDecode(b.read<String>('content_json'))
              as Map<String, dynamic>;
        } catch (_) {
          content = {};
        }
        return <String, dynamic>{
          'id': b.read<String>('id'),
          'noteId': b.read<String>('note_id'),
          'blockType': b.read<String>('block_type'),
          'content': content,
          'orderIndex': b.read<int>('order_index'),
          'updatedAt': b.read<int>('updated_at'),
          'version': b.read<int>('version'),
          'deleted': b.read<int>('deleted'),
          'createdAt': b.read<int>('created_at'),
          'section': b.read<String>('section'),
        };
      }).toList();

      await customStatement(
        'UPDATE sync_notes SET document_json = ? WHERE id = ?',
        [jsonEncode(blockJsonList), noteId],
      );
    }
  }

  /// One-time migration: populate note_blocks_fts from all existing
  /// non-deleted blocks.
  Future<void> _backfillNoteBlocksFts() async {
    final blocks = await customSelect(
      'SELECT id, note_id, content_json '
      'FROM note_blocks WHERE deleted = 0',
    ).get();

    for (final block in blocks) {
      final blockId = block.read<String>('id');
      final noteId = block.read<String>('note_id');
      final contentJsonStr = block.read<String>('content_json');
      final plainText = NoteBlockFtsService.extractPlainText(contentJsonStr);

      if (plainText.isNotEmpty) {
        await customStatement(
          'INSERT INTO note_blocks_fts(plain_text, note_id, block_id) '
          'VALUES (?, ?, ?)',
          [plainText, noteId, blockId],
        );
      }
    }
  }

  /// v21 migration: Create owner access records for all existing content entities.
  ///
  /// For every folder, note, song, prayer, and promise owned by a user,
  /// insert an entity_access record with accessType = 'owner'.
  Future<void> _migrateOwnerAccessRecords() async {
    final now = TestClock.now();

    // Entity tables and their type strings for entity_access
    final entityTables = [
      ('folders', 'folder'),
      ('sync_notes', 'note'),
      ('songs', 'song'),
      ('prayers', 'prayer'),
      ('promises', 'promise'),
    ];

    for (final (table, entityType) in entityTables) {
      final rows = await customSelect(
        'SELECT id, user_id FROM $table WHERE deleted = 0',
      ).get();

      for (final row in rows) {
        final entityId = row.read<String>('id');
        final userId = row.read<String>('user_id');
        final accessId =
            '${now.toRadixString(16)}-owner-${entityId.hashCode.toRadixString(16)}';

        await customStatement(
          'INSERT OR IGNORE INTO entity_access '
          '(id, entity_type, entity_id, access_type, target_id, role, '
          'user_id, updated_at, version, deleted, created_at) '
          'VALUES (?, ?, ?, ?, NULL, ?, ?, ?, 1, 0, ?)',
          [accessId, entityType, entityId, 'owner', 'owner', userId, now, now],
        );
      }
    }
  }

  /// v21 migration: Migrate SharedPrayers → entity_access records.
  ///
  /// Each SharedPrayer becomes a 'public' entity_access (share code grants
  /// public-like access). The share code is preserved in the share_codes table.
  Future<void> _migrateSharedPrayersToEntityAccess() async {
    final now = TestClock.now();

    final rows = await customSelect(
      'SELECT id, prayer_id, shared_by_user_id, share_code, '
      'allow_editing, user_id '
      'FROM shared_prayers WHERE deleted = 0',
    ).get();

    for (final row in rows) {
      final sharedPrayerId = row.read<String>('id');
      final prayerId = row.read<String>('prayer_id');
      final userId = row.read<String>('user_id');
      final shareCode = row.read<String>('share_code');
      final allowEditing = row.read<int>('allow_editing');

      final accessId =
          '${now.toRadixString(16)}-sp-${sharedPrayerId.hashCode.toRadixString(16)}';
      final role = allowEditing == 1 ? 'editor' : 'viewer';

      // Create entity_access record
      await customStatement(
        'INSERT OR IGNORE INTO entity_access '
        '(id, entity_type, entity_id, access_type, target_id, role, '
        'user_id, updated_at, version, deleted, created_at) '
        'VALUES (?, ?, ?, ?, NULL, ?, ?, ?, 1, 0, ?)',
        [accessId, 'prayer', prayerId, 'public', role, userId, now, now],
      );

      // Preserve share code mapping
      if (shareCode.isNotEmpty) {
        await customStatement(
          'INSERT OR IGNORE INTO share_codes '
          '(code, entity_access_id, entity_type, entity_id) '
          'VALUES (?, ?, ?, ?)',
          [shareCode, accessId, 'prayer', prayerId],
        );
      }
    }
  }

  /// v21 migration: Migrate PrayerCollaborators → entity_access records.
  ///
  /// Each PrayerCollaborator becomes a 'user' entity_access with the
  /// appropriate role mapping (collaborator → editor, viewer → viewer).
  Future<void> _migratePrayerCollaboratorsToEntityAccess() async {
    final now = TestClock.now();

    final rows = await customSelect(
      'SELECT id, prayer_id, collaborator_user_id, role, user_id '
      'FROM prayer_collaborators WHERE deleted = 0',
    ).get();

    for (final row in rows) {
      final collabId = row.read<String>('id');
      final prayerId = row.read<String>('prayer_id');
      final collaboratorUserId = row.read<String>('collaborator_user_id');
      final oldRole = row.read<String>('role');
      final userId = row.read<String>('user_id');

      final accessId =
          '${now.toRadixString(16)}-pc-${collabId.hashCode.toRadixString(16)}';

      // Map old roles to new roles
      String newRole;
      switch (oldRole) {
        case 'owner':
          newRole = 'owner';
          break;
        case 'collaborator':
          newRole = 'editor';
          break;
        default:
          newRole = 'viewer';
      }

      await customStatement(
        'INSERT OR IGNORE INTO entity_access '
        '(id, entity_type, entity_id, access_type, target_id, role, '
        'user_id, updated_at, version, deleted, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?)',
        [
          accessId, 'prayer', prayerId, 'user',
          collaboratorUserId, newRole, userId, now, now,
        ],
      );
    }
  }

  Future<void> _ensureUserProfileColumns() async {
    final tableRows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='user_profiles'",
    ).get();
    if (tableRows.isEmpty) return;

    final profileCols = await customSelect(
      "PRAGMA table_info(user_profiles)",
    ).get();
    final colNames = profileCols.map((r) => r.read<String>('name')).toSet();

    if (!colNames.contains('username')) {
      await customStatement(
        "ALTER TABLE user_profiles ADD COLUMN username TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!colNames.contains('display_name')) {
      await customStatement(
        "ALTER TABLE user_profiles ADD COLUMN display_name TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!colNames.contains('bio')) {
      await customStatement(
        "ALTER TABLE user_profiles ADD COLUMN bio TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  // ==================== Indexes ====================

  /// Create indexes for optimal query performance
  /// Called after migration if needed
  Future<void> createIndexes() async {
    // Folders indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_folders_parent
      ON folders(parent_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_folders_user
      ON folders(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_folders_updated
      ON folders(updated_at)
    ''');

    // Notes indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_notes_folder
      ON sync_notes(folder_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_notes_user
      ON sync_notes(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_notes_updated
      ON sync_notes(updated_at)
    ''');

    // Note blocks indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_blocks_note
      ON note_blocks(note_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_blocks_order
      ON note_blocks(note_id, order_index) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_blocks_updated
      ON note_blocks(updated_at)
    ''');

    // Prayers indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayers_user
      ON prayers(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayers_updated
      ON prayers(updated_at)
    ''');

    // Promises indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_promises_user
      ON promises(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_promises_updated
      ON promises(updated_at)
    ''');

    // People indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_people_user
      ON people(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_people_updated
      ON people(updated_at)
    ''');

    // Songs indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_songs_user
      ON songs(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_songs_folder
      ON songs(folder_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_songs_language
      ON songs(language) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_songs_title
      ON songs(title) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_songs_updated
      ON songs(updated_at)
    ''');

    // Prayer logs indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayer_logs_prayer
      ON prayer_logs(prayer_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayer_logs_session
      ON prayer_logs(session_date, prayer_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayer_logs_user
      ON prayer_logs(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayer_logs_updated
      ON prayer_logs(updated_at)
    ''');

    // User profiles indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_user_profiles_user
      ON user_profiles(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_user_profiles_username
      ON user_profiles(username) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_user_profiles_updated
      ON user_profiles(updated_at)
    ''');

    // Friendships indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_friendships_user
      ON friendships(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_friendships_friend
      ON friendships(friend_user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_friendships_updated
      ON friendships(updated_at)
    ''');

    // Friend requests indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_friend_requests_to
      ON friend_requests(to_user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_friend_requests_from
      ON friend_requests(from_user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_friend_requests_updated
      ON friend_requests(updated_at)
    ''');

    // Blocked users indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_blocked_users_user
      ON blocked_users(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_blocked_users_updated
      ON blocked_users(updated_at)
    ''');

    // Shared prayers indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_shared_prayers_prayer
      ON shared_prayers(prayer_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_shared_prayers_code
      ON shared_prayers(share_code) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_shared_prayers_user
      ON shared_prayers(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_shared_prayers_updated
      ON shared_prayers(updated_at)
    ''');

    // Prayer collaborators indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayer_collabs_prayer
      ON prayer_collaborators(prayer_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayer_collabs_collaborator
      ON prayer_collaborators(collaborator_user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_prayer_collabs_updated
      ON prayer_collaborators(updated_at)
    ''');

    // Groups indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_groups_user
      ON groups(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_groups_updated
      ON groups(updated_at)
    ''');

    // Group members indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_group_members_group
      ON group_members(group_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_group_members_user
      ON group_members(user_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_group_members_updated
      ON group_members(updated_at)
    ''');

    // Group prayers indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_group_prayers_group
      ON group_prayers(group_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_group_prayers_prayer
      ON group_prayers(prayer_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_group_prayers_updated
      ON group_prayers(updated_at)
    ''');

    // Group announcements indexes
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_group_announcements_group
      ON group_announcements(group_id) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_group_announcements_updated
      ON group_announcements(updated_at)
    ''');

    // Note revisions indexes (local-only)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_note_revisions_note
      ON note_revisions(note_id)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_note_revisions_created
      ON note_revisions(note_id, created_at DESC)
    ''');

    // Bible highlights indexes (local-only)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_bible_highlights_lookup
      ON bible_highlights(book_id, chapter)
    ''');

    // Entity access indexes (v21 — ACL)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_entity_access_entity
      ON entity_access(entity_id, access_type) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_entity_access_user_type
      ON entity_access(user_id, entity_type) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_entity_access_target
      ON entity_access(target_id, access_type) WHERE deleted = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_entity_access_updated
      ON entity_access(updated_at)
    ''');

    // Document operations indexes (v21 — CRDT foundation, local-only)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_doc_ops_entity
      ON document_operations(entity_id, sequence_number)
    ''');

    // Oplog indexes (critical for sync performance)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_oplog_unsynced
      ON oplog(synced, timestamp) WHERE synced = 0
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_oplog_entity
      ON oplog(entity_type, entity_id)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_oplog_timestamp
      ON oplog(timestamp)
    ''');
  }

  // ==================== Utility Methods ====================

  /// Get count of pending (unsynced, non-failed) operations
  Future<int> getPendingOpsCount() async {
    final result = await customSelect(
      'SELECT COUNT(*) as count FROM oplog WHERE synced = 0 AND failed_at IS NULL',
    ).getSingle();
    return result.read<int>('count');
  }

  /// Get all unsynced operations ordered by timestamp, excluding quarantined ops
  Future<List<OplogData>> getUnsyncedOps({int? limit}) async {
    var query = select(oplog)
      ..where((o) => o.synced.equals(0) & o.failedAt.isNull())
      ..orderBy([(o) => OrderingTerm.asc(o.timestamp)]);

    if (limit != null) {
      query = query..limit(limit);
    }

    return query.get();
  }

  /// Quarantine a permanently failing operation so it stops blocking the push queue.
  Future<void> markOpFailed(String opId, String reason) async {
    await (update(oplog)..where((o) => o.opId.equals(opId))).write(
      OplogCompanion(
        failedAt: Value(TestClock.now()),
        failedReason: Value(reason),
      ),
    );
  }

  /// Mark operations as synced
  Future<void> markOpsSynced(List<String> opIds) async {
    await (update(oplog)..where((o) => o.opId.isIn(opIds))).write(
      const OplogCompanion(synced: Value(1)),
    );
  }

  /// Mark a single operation as synced and store its server timestamp
  Future<void> markOpSyncedWithTimestamp(String opId, int serverTimestamp) async {
    await (update(oplog)..where((o) => o.opId.equals(opId))).write(
      OplogCompanion(
        synced: const Value(1),
        serverTimestamp: Value(serverTimestamp),
      ),
    );
  }

  /// Purge old synced oplog entries and soft-deleted records
  ///
  /// Removes synced oplog entries older than [retentionDays] and
  /// hard-deletes soft-deleted entity records older than [retentionDays].
  /// This prevents unbounded database growth.
  Future<PurgeResult> purgeOldData({int retentionDays = 30}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;

    var oplogPurged = 0;
    var entitiesPurged = 0;

    // Each table is purged independently rather than in a single transaction.
    // There is no cross-table consistency requirement for GC, and a single
    // transaction across all entity tables could hold a long write lock.

    // Purge synced oplog entries older than cutoff
    oplogPurged = await (delete(oplog)
          ..where(
              (o) => o.synced.equals(1) & o.timestamp.isSmallerThanValue(cutoff)))
        .go();

    // Hard-delete soft-deleted entities older than cutoff
    entitiesPurged += await (delete(folders)
          ..where((f) =>
              f.deleted.equals(1) & f.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(syncNotes)
          ..where((n) =>
              n.deleted.equals(1) & n.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(noteBlocks)
          ..where((b) =>
              b.deleted.equals(1) & b.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(prayers)
          ..where((p) =>
              p.deleted.equals(1) & p.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(promises)
          ..where((p) =>
              p.deleted.equals(1) & p.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(people)
          ..where((p) =>
              p.deleted.equals(1) & p.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(songs)
          ..where((s) =>
              s.deleted.equals(1) & s.updatedAt.isSmallerThanValue(cutoff)))
        .go();

    // v4 sync entity tables
    entitiesPurged += await (delete(prayerLogs)
          ..where((p) =>
              p.deleted.equals(1) & p.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    // Social tables (userProfiles, friendships, friendRequests, blockedUsers,
    // sharedPrayers, prayerCollaborators, groups, groupMembers, groupPrayers,
    // groupAnnouncements) are now online-required — no local purge needed.

    // v9+ tables
    entitiesPurged += await (delete(prayerUpdates)
          ..where((p) =>
              p.deleted.equals(1) & p.updatedAt.isSmallerThanValue(cutoff)))
        .go();

    // v10 tables
    entitiesPurged += await (delete(promiseConditions)
          ..where((c) =>
              c.deleted.equals(1) & c.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(syncPromiseTags)
          ..where((pt) =>
              pt.deleted.equals(1) & pt.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(syncPrayerTags)
          ..where((pt) =>
              pt.deleted.equals(1) & pt.updatedAt.isSmallerThanValue(cutoff)))
        .go();
    entitiesPurged += await (delete(syncPrayerPeople)
          ..where((pp) =>
              pp.deleted.equals(1) & pp.updatedAt.isSmallerThanValue(cutoff)))
        .go();

    // v12 tables
    entitiesPurged += await (delete(syncSongTags)
          ..where((st) =>
              st.deleted.equals(1) & st.updatedAt.isSmallerThanValue(cutoff)))
        .go();

    // v17 tables
    entitiesPurged += await (delete(promisePrayerLinks)
          ..where((l) =>
              l.deleted.equals(1) & l.updatedAt.isSmallerThanValue(cutoff)))
        .go();

    // v21 tables
    entitiesPurged += await (delete(entityAccess)
          ..where((e) =>
              e.deleted.equals(1) & e.updatedAt.isSmallerThanValue(cutoff)))
        .go();

    // Clean up old document operations (local-only, no soft delete)
    await (delete(documentOperations)
          ..where((d) => d.timestamp.isSmallerThanValue(cutoff)))
        .go();

    // Clean up orphaned note revisions whose parent note was hard-deleted.
    await customStatement(
      'DELETE FROM note_revisions WHERE note_id NOT IN '
      '(SELECT id FROM sync_notes)',
    );

    return PurgeResult(
      oplogEntriesPurged: oplogPurged,
      entitiesPurged: entitiesPurged,
    );
  }

  /// Get or create current device
  Future<Device> getOrCreateCurrentDevice({
    required String deviceName,
    required String platform,
    required String appVersion,
  }) async {
    final existing = await (select(devices)
          ..where((d) => d.isCurrentDevice.equals(1)))
        .getSingleOrNull();

    if (existing != null) {
      // Update last active timestamp
      await (update(devices)..where((d) => d.id.equals(existing.id))).write(
        DevicesCompanion(lastActiveAt: Value(TestClock.now())),
      );
      return existing;
    }

    // Create new device
    final deviceId = _generateUuid();
    final now = TestClock.now();

    final companion = DevicesCompanion.insert(
      id: deviceId,
      name: deviceName,
      platform: platform,
      appVersion: appVersion,
      createdAt: now,
      lastActiveAt: now,
      isCurrentDevice: const Value(1),
    );

    await into(devices).insert(companion);

    return (select(devices)..where((d) => d.id.equals(deviceId))).getSingle();
  }

  /// Update sync state
  Future<void> updateSyncState(SyncStateCompanion companion) async {
    await (update(syncState)..where((s) => s.id.equals(1))).write(companion);
  }

  /// Get current sync state
  Future<SyncStateData> getSyncState() async {
    return (select(syncState)..where((s) => s.id.equals(1))).getSingle();
  }

  /// Clear all user data and reset sync state.
  ///
  /// Called during logout / account switch so the next login starts
  /// with an empty local database and a fresh sync pull (cursor = null).
  Future<void> clearAllUserData() async {
    // Delete all entity data
    await delete(folders).go();
    await delete(syncNotes).go();
    await delete(noteBlocks).go();
    await delete(prayers).go();
    await delete(promises).go();
    await delete(people).go();
    await delete(songs).go();
    await delete(prayerLogs).go();
    // Social tables are online-required — no local data to clear.
    await delete(syncPreachers).go();
    await delete(syncTags).go();
    await delete(syncNoteTags).go();
    await delete(bibleCache).go();
    await delete(prayerUpdates).go();
    await delete(promiseConditions).go();
    await delete(syncPromiseTags).go();
    await delete(syncPrayerTags).go();
    await delete(syncPrayerPeople).go();
    await delete(syncSongTags).go();
    await delete(noteRevisions).go();
    await delete(promisePrayerLinks).go();
    await delete(bibleHighlights).go();
    // v21 tables
    await delete(entityAccess).go();
    await delete(documentOperations).go();
    await delete(shareCodes).go();

    // Clear the oplog
    await delete(oplog).go();

    // Reset sync state cursor so the next sync does a full pull
    await updateSyncState(
      SyncStateCompanion(
        syncStatus: const Value(SyncStatus.idle),
        lastPushTimestamp: const Value(null),
        lastPullTimestamp: const Value(null),
        lastRemoteCursor: const Value(null),
        pendingOpsCount: const Value(0),
        consecutiveFailures: const Value(0),
        lastSyncAttempt: const Value(null),
        lastError: const Value(null),
      ),
    );
  }

  // Simple UUID generator (consider using uuid package in production)
  String _generateUuid() {
    final now = TestClock.now();
    final random = now.hashCode;
    return '${now.toRadixString(16)}-${random.toRadixString(16)}';
  }
}

/// Result of a purge operation
class PurgeResult {
  /// Number of synced oplog entries removed
  final int oplogEntriesPurged;

  /// Number of soft-deleted entities hard-deleted
  final int entitiesPurged;

  const PurgeResult({
    required this.oplogEntriesPurged,
    required this.entitiesPurged,
  });

  /// Whether any data was purged
  bool get hadWork => oplogEntriesPurged > 0 || entitiesPurged > 0;

  @override
  String toString() =>
      'PurgeResult(oplog: $oplogEntriesPurged, entities: $entitiesPurged)';
}

/// Open connection to SQLite database
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, AppConfig.dbName));
    return NativeDatabase.createInBackground(file);
  });
}
