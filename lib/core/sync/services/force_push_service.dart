import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/sync_database.dart';
import '../models/oplog_entry.dart';
import '../utils/sync_logger.dart';
import '../../testing/test_clock.dart';

/// Progress callback for force push operations.
/// [tableName] is a human-readable label, [tableIndex] is 0-based,
/// [totalTables] is the total number of tables to process.
typedef ForcePushProgressCallback = void Function(
  String tableName,
  int tableIndex,
  int totalTables,
);

/// Service that creates INSERT oplog entries for every row in every
/// syncable table, allowing a full force push of all local data to
/// the remote database regardless of existing oplog state.
class ForcePushService {
  final SyncDatabase _db;
  final String _deviceId;
  static const _uuid = Uuid();

  /// Total number of syncable tables.
  static const totalTables = 34;

  ForcePushService({
    required SyncDatabase db,
    required String deviceId,
  })  : _db = db,
        _deviceId = deviceId;

  /// Creates INSERT oplog entries for all data in all syncable tables.
  /// Returns the total number of oplog entries created.
  /// If [onProgress] is provided it is called before each table is processed.
  Future<int> createForcePushOplogs({
    ForcePushProgressCallback? onProgress,
  }) async {
    var totalCount = 0;
    var idx = 0;
    final now = TestClock.now();

    SyncLogger.info('Force push: starting oplog generation for all tables');

    final steps = <(String, Future<int> Function(int))>[
      ('Folders', _processFolders),
      ('Notes', _processNotes),
      ('Note Blocks', _processNoteBlocks),
      ('Prayers', _processPrayers),
      ('Promises', _processPromises),
      ('People', _processPeople),
      ('Songs', _processSongs),
      ('Prayer Logs', _processPrayerLogs),
      ('Prayer Updates', _processPrayerUpdates),
      ('Promise Conditions', _processPromiseConditions),
      ('User Profiles', _processUserProfiles),
      ('Friendships', _processFriendships),
      ('Friend Requests', _processFriendRequests),
      ('Blocked Users', _processBlockedUsers),
      ('Shared Prayers', _processSharedPrayers),
      ('Prayer Collaborators', _processPrayerCollaborators),
      ('Groups', _processGroups),
      ('Group Members', _processGroupMembers),
      ('Group Prayers', _processGroupPrayers),
      ('Group Announcements', _processGroupAnnouncements),
      ('Pending Group Members', _processPendingGroupMembers),
      ('Tags', _processTags),
      ('Note Tags', _processNoteTags),
      ('Prayer Tags', _processPrayerTags),
      ('Promise Tags', _processPromiseTags),
      ('Song Tags', _processSongTags),
      ('Prayer People', _processPrayerPeople),
      ('Preachers', _processPreachers),
      ('Promise Prayer Links', _processPromisePrayerLinks),
      ('Entity Access', _processEntityAccess),
      ('Feedback Threads', _processFeedbackThreads),
      ('Feedback Messages', _processFeedbackMessages),
      ('Feedback Attachments', _processFeedbackAttachments),
      ('Bible Reference History', _processBibleReferenceHistory),
    ];

    for (final (label, processor) in steps) {
      onProgress?.call(label, idx, steps.length);
      totalCount += await processor(now);
      idx++;
    }

    SyncLogger.info('Force push: created $totalCount oplog entries');
    return totalCount;
  }

  // ==================== Table Processors ====================

  Future<int> _processFolders(int timestamp) async {
    final rows = await _db.select(_db.folders).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'folder',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'parentId': r.parentId,
            'name': r.name,
            'type': r.type,
            'visibility': r.visibility,
            'groupId': r.groupId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} folders');
    return rows.length;
  }

  Future<int> _processNotes(int timestamp) async {
    final rows = await _db.select(_db.syncNotes).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'note',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'folderId': r.folderId,
            'userId': r.userId,
            'title': r.title,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
            'preacherId': r.preacherId,
            'noteDate': r.noteDate,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} notes');
    return rows.length;
  }

  Future<int> _processNoteBlocks(int timestamp) async {
    final rows = await _db.select(_db.noteBlocks).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        // contentJson is stored as a JSON string; decode to Map for payload
        dynamic content;
        try {
          content = jsonDecode(r.contentJson);
        } catch (_) {
          content = r.contentJson;
        }
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'note_block',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'noteId': r.noteId,
            'blockType': r.blockType,
            'content': content,
            'orderIndex': r.orderIndex,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
            'section': r.section,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} note blocks');
    return rows.length;
  }

  Future<int> _processPrayers(int timestamp) async {
    final rows = await _db.select(_db.prayers).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'prayer',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'title': r.title,
            'content': r.content,
            'frequency': r.frequency,
            'status': r.status,
            'category': r.category,
            'reminderAt': r.reminderAt,
            'answeredAt': r.answeredAt,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} prayers');
    return rows.length;
  }

  Future<int> _processPromises(int timestamp) async {
    final rows = await _db.select(_db.promises).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'promise',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'reference': r.reference,
            'content': r.content,
            'preview': r.preview,
            'notes': r.notes,
            'category': r.category,
            'isFavorite': r.isFavorite,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} promises');
    return rows.length;
  }

  Future<int> _processPeople(int timestamp) async {
    final rows = await _db.select(_db.people).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'person',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'name': r.name,
            'relation': r.relation,
            'church': r.church,
            'email': r.email,
            'phone': r.phone,
            'notes': r.notes,
            'imageUrl': r.imageUrl,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} people');
    return rows.length;
  }

  Future<int> _processSongs(int timestamp) async {
    final rows = await _db.select(_db.songs).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'song',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'title': r.title,
            'folderId': r.folderId,
            'lyrics': r.lyrics,
            'chords': r.chords,
            'scale': r.scale,
            'chordLines': r.chordLines,
            'language': r.language,
            'book': r.book,
            'preview': r.preview,
            'tags': r.tags,
            'hasChords': r.hasChords,
            'isFavorite': r.isFavorite,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} songs');
    return rows.length;
  }

  Future<int> _processPrayerLogs(int timestamp) async {
    final rows = await _db.select(_db.prayerLogs).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'prayer_log',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'prayerId': r.prayerId,
            'userId': r.userId,
            'note': r.note,
            'loggedAt': r.loggedAt,
            'sessionDate': r.sessionDate,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} prayer logs');
    return rows.length;
  }

  Future<int> _processPrayerUpdates(int timestamp) async {
    final rows = await _db.select(_db.prayerUpdates).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'prayer_update',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'prayerId': r.prayerId,
            'userId': r.userId,
            'content': r.content,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} prayer updates');
    return rows.length;
  }

  Future<int> _processPromiseConditions(int timestamp) async {
    final rows = await _db.select(_db.promiseConditions).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'promise_condition',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'promiseId': r.promiseId,
            'userId': r.userId,
            'description': r.description,
            'notes': r.notes,
            'status': r.status,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} promise conditions');
    return rows.length;
  }

  Future<int> _processUserProfiles(int timestamp) async {
    final rows = await _db.select(_db.userProfiles).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'user_profile',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'username': r.username,
            'displayName': r.displayName,
            'bio': r.bio,
            'imageUrl': r.imageUrl,
            'friendRequestsEnabled': r.friendRequestsEnabled,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} user profiles');
    return rows.length;
  }

  Future<int> _processFriendships(int timestamp) async {
    final rows = await _db.select(_db.friendships).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'friendship',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'friendUserId': r.friendUserId,
            'friendUsername': r.friendUsername,
            'friendDisplayName': r.friendDisplayName,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} friendships');
    return rows.length;
  }

  Future<int> _processFriendRequests(int timestamp) async {
    final rows = await _db.select(_db.friendRequests).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'friend_request',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'fromUserId': r.fromUserId,
            'fromUsername': r.fromUsername,
            'fromDisplayName': r.fromDisplayName,
            'toUserId': r.toUserId,
            'toUsername': r.toUsername,
            'toDisplayName': r.toDisplayName,
            'status': r.status,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} friend requests');
    return rows.length;
  }

  Future<int> _processBlockedUsers(int timestamp) async {
    final rows = await _db.select(_db.blockedUsers).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'blocked_user',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'blockedUserId': r.blockedUserId,
            'blockedUsername': r.blockedUsername,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} blocked users');
    return rows.length;
  }

  Future<int> _processSharedPrayers(int timestamp) async {
    final rows = await _db.select(_db.sharedPrayers).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'shared_prayer',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'prayerId': r.prayerId,
            'sharedByUserId': r.sharedByUserId,
            'shareCode': r.shareCode,
            'allowEditing': r.allowEditing,
            'allowLogging': r.allowLogging,
            'allowUpdates': r.allowUpdates,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} shared prayers');
    return rows.length;
  }

  Future<int> _processPrayerCollaborators(int timestamp) async {
    final rows = await _db.select(_db.prayerCollaborators).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'prayer_collaborator',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'prayerId': r.prayerId,
            'sharedPrayerId': r.sharedPrayerId,
            'collaboratorUserId': r.collaboratorUserId,
            'collaboratorUsername': r.collaboratorUsername,
            'role': r.role,
            'addedByUserId': r.addedByUserId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} prayer collaborators');
    return rows.length;
  }

  Future<int> _processGroups(int timestamp) async {
    final rows = await _db.select(_db.groups).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'group',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'name': r.name,
            'description': r.description,
            'groupType': r.groupType,
            'imageUrl': r.imageUrl,
            'joinCode': r.joinCode,
            'joinPolicy': r.joinPolicy,
            'createdByUserId': r.createdByUserId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} groups');
    return rows.length;
  }

  Future<int> _processGroupMembers(int timestamp) async {
    final rows = await _db.select(_db.groupMembers).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'group_member',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'groupId': r.groupId,
            'memberUserId': r.memberUserId,
            'memberUsername': r.memberUsername,
            'memberDisplayName': r.memberDisplayName,
            'role': r.role,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} group members');
    return rows.length;
  }

  Future<int> _processGroupPrayers(int timestamp) async {
    final rows = await _db.select(_db.groupPrayers).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'group_prayer',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'groupId': r.groupId,
            'prayerId': r.prayerId,
            'addedByUserId': r.addedByUserId,
            'addedByUsername': r.addedByUsername,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} group prayers');
    return rows.length;
  }

  Future<int> _processGroupAnnouncements(int timestamp) async {
    final rows = await _db.select(_db.groupAnnouncements).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'group_announcement',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'groupId': r.groupId,
            'title': r.title,
            'content': r.content,
            'authorUserId': r.authorUserId,
            'authorUsername': r.authorUsername,
            'pinned': r.pinned,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} group announcements');
    return rows.length;
  }

  Future<int> _processPendingGroupMembers(int timestamp) async {
    final rows = await _db.select(_db.pendingGroupMembers).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'pending_group_member',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'groupId': r.groupId,
            'requestingUserId': r.requestingUserId,
            'requestingUsername': r.requestingUsername,
            'status': r.status,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} pending group members');
    return rows.length;
  }

  Future<int> _processTags(int timestamp) async {
    final rows = await _db.select(_db.syncTags).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'tag',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'name': r.name,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} tags');
    return rows.length;
  }

  Future<int> _processNoteTags(int timestamp) async {
    final rows = await _db.select(_db.syncNoteTags).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'note_tag',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'noteId': r.noteId,
            'tagId': r.tagId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} note tags');
    return rows.length;
  }

  Future<int> _processPrayerTags(int timestamp) async {
    final rows = await _db.select(_db.syncPrayerTags).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'prayer_tag',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'prayerId': r.prayerId,
            'tagId': r.tagId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} prayer tags');
    return rows.length;
  }

  Future<int> _processPromiseTags(int timestamp) async {
    final rows = await _db.select(_db.syncPromiseTags).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'promise_tag',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'promiseId': r.promiseId,
            'tagId': r.tagId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} promise tags');
    return rows.length;
  }

  Future<int> _processSongTags(int timestamp) async {
    final rows = await _db.select(_db.syncSongTags).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'song_tag',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'songId': r.songId,
            'tagId': r.tagId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} song tags');
    return rows.length;
  }

  Future<int> _processPrayerPeople(int timestamp) async {
    final rows = await _db.select(_db.syncPrayerPeople).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'prayer_person',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'prayerId': r.prayerId,
            'personId': r.personId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} prayer people');
    return rows.length;
  }

  Future<int> _processPreachers(int timestamp) async {
    final rows = await _db.select(_db.syncPreachers).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'preacher',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'name': r.name,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} preachers');
    return rows.length;
  }

  Future<int> _processPromisePrayerLinks(int timestamp) async {
    final rows = await _db.select(_db.promisePrayerLinks).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'promise_prayer_link',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'promiseId': r.promiseId,
            'prayerId': r.prayerId,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} promise prayer links');
    return rows.length;
  }

  Future<int> _processEntityAccess(int timestamp) async {
    final rows = await _db.select(_db.entityAccess).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'entity_access',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'entityType': r.entityType,
            'entityId': r.entityId,
            'accessType': r.accessType,
            'targetId': r.targetId,
            'role': r.role,
            'userId': r.userId,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} entity access');
    return rows.length;
  }

  Future<int> _processFeedbackThreads(int timestamp) async {
    final rows = await _db.select(_db.feedbackThreads).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'feedback_thread',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'category': r.category,
            'subject': r.subject,
            'status': r.status,
            'priority': r.priority,
            'lastMessageAt': r.lastMessageAt,
            'adminAssigned': r.adminAssigned,
            'unreadForUser': r.unreadForUser,
            'unreadForAdmin': r.unreadForAdmin,
            'deviceModel': r.deviceModel,
            'osVersion': r.osVersion,
            'appVersion': r.appVersion,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} feedback threads');
    return rows.length;
  }

  Future<int> _processFeedbackMessages(int timestamp) async {
    final rows = await _db.select(_db.feedbackMessages).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'feedback_message',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'threadId': r.threadId,
            'userId': r.userId,
            'message': r.message,
            'senderType': r.senderType,
            'hasAttachments': r.hasAttachments,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} feedback messages');
    return rows.length;
  }

  Future<int> _processFeedbackAttachments(int timestamp) async {
    final rows = await _db.select(_db.feedbackAttachments).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'feedback_attachment',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'messageId': r.messageId,
            'url': r.url,
            'type': r.type,
            'size': r.size,
            'fileName': r.fileName,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} feedback attachments');
    return rows.length;
  }

  Future<int> _processBibleReferenceHistory(int timestamp) async {
    final rows = await _db.select(_db.bibleReferenceHistory).get();
    if (rows.isEmpty) return 0;
    await _db.batch((batch) {
      for (final r in rows) {
        batch.insert(_db.oplog, _makeOplog(
          entityType: 'bible_reference_history',
          entityId: r.id,
          entityVersion: r.version,
          timestamp: timestamp,
          payload: {
            'id': r.id,
            'userId': r.userId,
            'book': r.book,
            'chapter': r.chapter,
            'verseStart': r.verseStart,
            'verseEnd': r.verseEnd,
            'translation': r.translation,
            'openedAt': r.openedAt,
            'updatedAt': r.updatedAt,
            'version': r.version,
            'deleted': r.deleted,
            'createdAt': r.createdAt,
          },
        ));
      }
    });
    SyncLogger.debug('Force push: ${rows.length} bible reference history');
    return rows.length;
  }

  // ==================== Helper ====================

  OplogCompanion _makeOplog({
    required String entityType,
    required String entityId,
    required int entityVersion,
    required int timestamp,
    required Map<String, dynamic> payload,
  }) {
    return OplogCompanion(
      opId: Value(_uuid.v4()),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(OplogOperation.insert.toDbValue()),
      payloadJson: Value(jsonEncode(payload)),
      timestamp: Value(timestamp),
      deviceId: Value(_deviceId),
      synced: const Value(0),
      entityVersion: Value(entityVersion),
      serverTimestamp: const Value(null),
    );
  }
}
