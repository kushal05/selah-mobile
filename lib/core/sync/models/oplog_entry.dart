import 'dart:convert';

import '../../testing/test_clock.dart';

/// Types of operations recorded in the oplog
enum OplogOperation {
  insert,
  update,
  delete;

  String toDbValue() {
    switch (this) {
      case OplogOperation.insert:
        return 'INSERT';
      case OplogOperation.update:
        return 'UPDATE';
      case OplogOperation.delete:
        return 'DELETE';
    }
  }

  static OplogOperation fromDbValue(String value) {
    switch (value) {
      case 'INSERT':
        return OplogOperation.insert;
      case 'UPDATE':
        return OplogOperation.update;
      case 'DELETE':
        return OplogOperation.delete;
      default:
        throw ArgumentError('Unknown operation: $value');
    }
  }
}

/// Types of entities tracked in the oplog
enum OplogEntityType {
  folder,
  note,
  noteBlock,
  prayer,
  promise,
  person,
  song,
  prayerLog,
  userProfile,
  friendship,
  friendRequest,
  blockedUser,
  sharedPrayer,
  prayerCollaborator,
  group,
  groupMember,
  groupPrayer,
  groupAnnouncement,
  preacher,
  tag,
  noteTag,
  prayerUpdate,
  promiseCondition,
  promiseTag,
  prayerTag,
  prayerPerson,
  songTag,
  pendingGroupMember,
  promisePrayerLink,
  entityAccess,
  feedbackThread,
  feedbackMessage,
  feedbackAttachment,
  bibleReferenceHistory,
  // Flutter-only pending Worker support (same pattern as feedbackThread).
  bibleHighlight,
  habitLog;

  String toDbValue() {
    switch (this) {
      case OplogEntityType.folder:
        return 'folder';
      case OplogEntityType.note:
        return 'note';
      case OplogEntityType.noteBlock:
        return 'note_block';
      case OplogEntityType.prayer:
        return 'prayer';
      case OplogEntityType.promise:
        return 'promise';
      case OplogEntityType.person:
        return 'person';
      case OplogEntityType.song:
        return 'song';
      case OplogEntityType.prayerLog:
        return 'prayer_log';
      case OplogEntityType.userProfile:
        return 'user_profile';
      case OplogEntityType.friendship:
        return 'friendship';
      case OplogEntityType.friendRequest:
        return 'friend_request';
      case OplogEntityType.blockedUser:
        return 'blocked_user';
      case OplogEntityType.sharedPrayer:
        return 'shared_prayer';
      case OplogEntityType.prayerCollaborator:
        return 'prayer_collaborator';
      case OplogEntityType.group:
        return 'group';
      case OplogEntityType.groupMember:
        return 'group_member';
      case OplogEntityType.groupPrayer:
        return 'group_prayer';
      case OplogEntityType.groupAnnouncement:
        return 'group_announcement';
      case OplogEntityType.preacher:
        return 'preacher';
      case OplogEntityType.tag:
        return 'tag';
      case OplogEntityType.noteTag:
        return 'note_tag';
      case OplogEntityType.prayerUpdate:
        return 'prayer_update';
      case OplogEntityType.promiseCondition:
        return 'promise_condition';
      case OplogEntityType.promiseTag:
        return 'promise_tag';
      case OplogEntityType.prayerTag:
        return 'prayer_tag';
      case OplogEntityType.prayerPerson:
        return 'prayer_person';
      case OplogEntityType.songTag:
        return 'song_tag';
      case OplogEntityType.pendingGroupMember:
        return 'pending_group_member';
      case OplogEntityType.promisePrayerLink:
        return 'promise_prayer_link';
      case OplogEntityType.entityAccess:
        return 'entity_access';
      case OplogEntityType.feedbackThread:
        return 'feedback_thread';
      case OplogEntityType.feedbackMessage:
        return 'feedback_message';
      case OplogEntityType.feedbackAttachment:
        return 'feedback_attachment';
      case OplogEntityType.bibleReferenceHistory:
        return 'bible_reference_history';
      case OplogEntityType.bibleHighlight:
        return 'bible_highlight';
      case OplogEntityType.habitLog:
        return 'habit_log';
    }
  }

  static OplogEntityType fromDbValue(String value) {
    switch (value) {
      case 'folder':
        return OplogEntityType.folder;
      case 'note':
        return OplogEntityType.note;
      case 'note_block':
        return OplogEntityType.noteBlock;
      case 'prayer':
        return OplogEntityType.prayer;
      case 'promise':
        return OplogEntityType.promise;
      case 'person':
        return OplogEntityType.person;
      case 'song':
        return OplogEntityType.song;
      case 'prayer_log':
        return OplogEntityType.prayerLog;
      case 'user_profile':
        return OplogEntityType.userProfile;
      case 'friendship':
        return OplogEntityType.friendship;
      case 'friend_request':
        return OplogEntityType.friendRequest;
      case 'blocked_user':
        return OplogEntityType.blockedUser;
      case 'shared_prayer':
        return OplogEntityType.sharedPrayer;
      case 'prayer_collaborator':
        return OplogEntityType.prayerCollaborator;
      case 'group':
        return OplogEntityType.group;
      case 'group_member':
        return OplogEntityType.groupMember;
      case 'group_prayer':
        return OplogEntityType.groupPrayer;
      case 'group_announcement':
        return OplogEntityType.groupAnnouncement;
      case 'preacher':
        return OplogEntityType.preacher;
      case 'tag':
        return OplogEntityType.tag;
      case 'note_tag':
        return OplogEntityType.noteTag;
      case 'prayer_update':
        return OplogEntityType.prayerUpdate;
      case 'promise_condition':
        return OplogEntityType.promiseCondition;
      case 'promise_tag':
        return OplogEntityType.promiseTag;
      case 'prayer_tag':
        return OplogEntityType.prayerTag;
      case 'prayer_person':
        return OplogEntityType.prayerPerson;
      case 'song_tag':
        return OplogEntityType.songTag;
      case 'pending_group_member':
        return OplogEntityType.pendingGroupMember;
      case 'promise_prayer_link':
        return OplogEntityType.promisePrayerLink;
      case 'entity_access':
        return OplogEntityType.entityAccess;
      case 'feedback_thread':
        return OplogEntityType.feedbackThread;
      case 'feedback_message':
        return OplogEntityType.feedbackMessage;
      case 'feedback_attachment':
        return OplogEntityType.feedbackAttachment;
      case 'bible_reference_history':
        return OplogEntityType.bibleReferenceHistory;
      case 'bible_highlight':
        return OplogEntityType.bibleHighlight;
      case 'habit_log':
        return OplogEntityType.habitLog;
      default:
        throw ArgumentError('Unknown entity type: $value');
    }
  }
}

/// Represents a single operation in the oplog
///
/// Per spec section 3.6:
/// - Every mutation creates exactly one oplog entry
/// - Oplog entries are immutable
/// - Never delete oplog rows (only mark synced)
class OplogEntry {
  /// Unique operation ID (UUID)
  final String opId;

  /// Type of entity being modified
  final OplogEntityType entityType;

  /// ID of the entity being modified
  final String entityId;

  /// Type of operation
  final OplogOperation operation;

  /// Full payload as JSON map
  final Map<String, dynamic> payload;

  /// Timestamp when operation was created (Unix milliseconds)
  final int timestamp;

  /// Device that created this operation
  final String deviceId;

  /// Whether this operation has been synced
  final bool synced;

  /// Version of the entity at time of operation
  final int entityVersion;

  /// Server-assigned timestamp (null until synced)
  final int? serverTimestamp;

  const OplogEntry({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.timestamp,
    required this.deviceId,
    required this.entityVersion,
    this.synced = false,
    this.serverTimestamp,
  });

  /// Create oplog entry for INSERT operation
  factory OplogEntry.insert({
    required String opId,
    required OplogEntityType entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    required String deviceId,
    required int entityVersion,
  }) {
    return OplogEntry(
      opId: opId,
      entityType: entityType,
      entityId: entityId,
      operation: OplogOperation.insert,
      payload: payload,
      timestamp: TestClock.now(),
      deviceId: deviceId,
      entityVersion: entityVersion,
    );
  }

  /// Create oplog entry for UPDATE operation
  factory OplogEntry.update({
    required String opId,
    required OplogEntityType entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    required String deviceId,
    required int entityVersion,
  }) {
    return OplogEntry(
      opId: opId,
      entityType: entityType,
      entityId: entityId,
      operation: OplogOperation.update,
      payload: payload,
      timestamp: TestClock.now(),
      deviceId: deviceId,
      entityVersion: entityVersion,
    );
  }

  /// Create oplog entry for DELETE operation
  factory OplogEntry.delete({
    required String opId,
    required OplogEntityType entityType,
    required String entityId,
    required Map<String, dynamic> payload,
    required String deviceId,
    required int entityVersion,
  }) {
    return OplogEntry(
      opId: opId,
      entityType: entityType,
      entityId: entityId,
      operation: OplogOperation.delete,
      payload: payload,
      timestamp: TestClock.now(),
      deviceId: deviceId,
      entityVersion: entityVersion,
    );
  }

  /// Convert to JSON for network transmission
  Map<String, dynamic> toJson() {
    return {
      'opId': opId,
      'entityType': entityType.toDbValue(),
      'entityId': entityId,
      'operation': operation.toDbValue(),
      'payload': payload,
      'timestamp': timestamp,
      'deviceId': deviceId,
      'entityVersion': entityVersion,
      'synced': synced,
      if (serverTimestamp != null) 'serverTimestamp': serverTimestamp,
    };
  }

  /// Normalize server payload: rename `_id` to `id` if `id` is absent.
  static Map<String, dynamic> _normalizePayload(Map<String, dynamic> p) {
    if (!p.containsKey('id') && p.containsKey('_id')) {
      final normalized = Map<String, dynamic>.from(p);
      normalized['id'] = normalized.remove('_id');
      return normalized;
    }
    return p;
  }

  /// Create from JSON
  factory OplogEntry.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'] is String
        ? jsonDecode(json['payload'] as String) as Map<String, dynamic>
        : json['payload'] as Map<String, dynamic>;
    return OplogEntry(
      opId: json['opId'] as String,
      entityType: OplogEntityType.fromDbValue(json['entityType'] as String),
      entityId: json['entityId'] as String,
      operation: OplogOperation.fromDbValue(json['operation'] as String),
      payload: _normalizePayload(rawPayload),
      timestamp: json['timestamp'] as int,
      deviceId: json['deviceId'] as String,
      entityVersion: json['entityVersion'] as int,
      synced: json['synced'] == true || json['synced'] == 1,
      serverTimestamp: json['serverTimestamp'] as int?,
    );
  }

  /// Get payload as JSON string
  String get payloadJson => jsonEncode(payload);

  /// Create a copy with synced = true
  OplogEntry markSynced({int? serverTs}) {
    return OplogEntry(
      opId: opId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      timestamp: timestamp,
      deviceId: deviceId,
      entityVersion: entityVersion,
      synced: true,
      serverTimestamp: serverTs ?? TestClock.now(),
    );
  }

  @override
  String toString() {
    return 'OplogEntry(opId: $opId, entity: $entityType/$entityId, '
        'op: $operation, v$entityVersion, synced: $synced)';
  }
}
