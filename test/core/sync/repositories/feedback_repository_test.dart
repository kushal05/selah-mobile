import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/sync/models/feedback_message_model.dart';
import 'package:notify/core/sync/models/feedback_thread_model.dart';
import 'package:notify/core/sync/repositories/feedback_message_repository.dart';
import 'package:notify/core/sync/repositories/feedback_thread_repository.dart';

const _userId = 'test-user';
const _deviceId = 'test-device';

void main() {
  late SyncDatabase db;
  late FeedbackThreadRepository threadRepo;
  late FeedbackMessageRepository messageRepo;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    threadRepo = FeedbackThreadRepository(db, _deviceId);
    messageRepo = FeedbackMessageRepository(db, _deviceId);
  });

  tearDown(() async {
    await db.close();
  });

  group('FeedbackThreadRepository', () {
    test('createThread creates a thread with oplog entry', () async {
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'App crashes on login',
      );

      expect(thread.id, isNotEmpty);
      expect(thread.userId, _userId);
      expect(thread.category, 'bug');
      expect(thread.subject, 'App crashes on login');
      expect(thread.status, 'open');
      expect(thread.version, 1);
      expect(thread.deleted, 0);

      // Verify oplog entry was created
      final oplog = await db.getUnsyncedOps();
      expect(oplog.any((o) => o.entityId == thread.id), true);
    });

    test('getUserThreads returns non-deleted threads for user', () async {
      await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Thread 1',
      );
      await threadRepo.createThread(
        userId: _userId,
        category: 'performance',
        subject: 'Thread 2',
      );
      await threadRepo.createThread(
        userId: 'other-user',
        category: 'bug',
        subject: 'Other user thread',
      );

      final threads = await threadRepo.getUserThreads(_userId);
      expect(threads, hasLength(2));
      expect(threads.every((t) => t.userId == _userId), true);
    });

    test('getUserThreads excludes soft-deleted threads', () async {
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'To be deleted',
      );

      await threadRepo.deleteThread(thread.id);

      final threads = await threadRepo.getUserThreads(_userId);
      expect(threads, isEmpty);
    });

    test('getUserThreads orders by lastMessageAt descending', () async {
      final thread1 = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'First',
      );
      // Small delay so timestamps differ
      await Future.delayed(const Duration(milliseconds: 10));
      await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Second',
      );

      final threads = await threadRepo.getUserThreads(_userId);
      expect(threads, hasLength(2));
      expect(threads.first.subject, 'Second');
      expect(threads.last.subject, 'First');

      // Update first thread's lastMessageAt to make it more recent
      await threadRepo.updateThread(
        id: thread1.id,
        lastMessageAt: DateTime.now().millisecondsSinceEpoch + 10000,
      );

      final reordered = await threadRepo.getUserThreads(_userId);
      expect(reordered.first.subject, 'First');
    });

    test('getThreadById returns thread', () async {
      final created = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Find me',
      );

      final found = await threadRepo.getThreadById(created.id);
      expect(found, isNotNull);
      expect(found!.subject, 'Find me');
    });

    test('getThreadById returns null for nonexistent', () async {
      final found = await threadRepo.getThreadById('nonexistent');
      expect(found, isNull);
    });

    test('watchUserThreads emits updates reactively', () async {
      final stream = threadRepo.watchUserThreads(_userId);

      // First emission: empty
      final first = await stream.first;
      expect(first, isEmpty);

      // Create a thread
      await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'New Thread',
      );

      // Next emission should contain the new thread
      final second = await stream.first;
      expect(second, hasLength(1));
      expect(second.first.subject, 'New Thread');
    });

    test('watchThreadById emits single thread updates', () async {
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Watch me',
      );

      final stream = threadRepo.watchThreadById(thread.id);

      final current = await stream.first;
      expect(current, isNotNull);
      expect(current!.status, 'open');

      // Update the thread
      await threadRepo.updateThread(id: thread.id, status: 'in_progress');

      final updated = await stream.first;
      expect(updated!.status, 'in_progress');
    });

    test('updateThread updates status and bumps version', () async {
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Update me',
      );

      final updated = await threadRepo.updateThread(
        id: thread.id,
        status: 'resolved',
      );

      expect(updated.status, 'resolved');
      expect(updated.version, 2);
      expect(updated.subject, thread.subject);
    });

    test('updateThread updates multiple fields', () async {
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Multi update',
      );

      final updated = await threadRepo.updateThread(
        id: thread.id,
        status: 'in_progress',
        adminAssigned: 'admin-1',
        lastMessageAt: 5000,
      );

      expect(updated.status, 'in_progress');
      expect(updated.adminAssigned, 'admin-1');
      expect(updated.lastMessageAt, 5000);
      expect(updated.version, 2);
    });

    test('updateThread creates oplog entry', () async {
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Oplog test',
      );

      final oplogBefore = await db.getUnsyncedOps();
      final countBefore = oplogBefore.length;

      await threadRepo.updateThread(id: thread.id, status: 'closed');

      final oplogAfter = await db.getUnsyncedOps();
      expect(oplogAfter.length, greaterThan(countBefore));
    });

    test('updateThread throws for nonexistent thread', () async {
      expect(
        () => threadRepo.updateThread(id: 'nonexistent', status: 'closed'),
        throwsA(isA<FeedbackThreadNotFoundException>()),
      );
    });

    test('deleteThread soft deletes and creates oplog', () async {
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Delete me',
      );

      await threadRepo.deleteThread(thread.id);

      // Should not appear in non-deleted queries
      final threads = await threadRepo.getUserThreads(_userId);
      expect(threads, isEmpty);

      // But should still exist in DB (soft delete)
      final raw = await threadRepo.getThreadById(thread.id);
      expect(raw, isNotNull);
      expect(raw!.isDeleted, true);
      expect(raw.version, 2);
    });

    test('deleteThread throws for nonexistent thread', () async {
      expect(
        () => threadRepo.deleteThread('nonexistent'),
        throwsA(isA<FeedbackThreadNotFoundException>()),
      );
    });
  });

  group('FeedbackMessageRepository', () {
    late FeedbackThreadModel testThread;

    setUp(() async {
      testThread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Test Thread',
      );
    });

    test('addMessage creates a message with oplog entry', () async {
      final msg = await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'Hello support',
      );

      expect(msg.id, isNotEmpty);
      expect(msg.threadId, testThread.id);
      expect(msg.userId, _userId);
      expect(msg.message, 'Hello support');
      expect(msg.senderType, 'user');
      expect(msg.version, 1);
      expect(msg.deleted, 0);

      // Verify oplog entry
      final oplog = await db.getUnsyncedOps();
      expect(oplog.any((o) => o.entityId == msg.id), true);
    });

    test('addMessage accepts custom senderType', () async {
      final msg = await messageRepo.addMessage(
        threadId: testThread.id,
        userId: 'admin-user',
        message: 'Admin reply',
        senderType: 'admin',
      );

      expect(msg.senderType, 'admin');
      expect(msg.isFromAdmin, true);
    });

    test('getThreadMessages returns non-deleted messages ordered by createdAt', () async {
      await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'First message',
      );
      await Future.delayed(const Duration(milliseconds: 10));
      await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'Second message',
      );

      final messages = await messageRepo.getThreadMessages(testThread.id);
      expect(messages, hasLength(2));
      expect(messages.first.message, 'First message');
      expect(messages.last.message, 'Second message');
    });

    test('getThreadMessages excludes soft-deleted messages', () async {
      final msg = await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'Delete me',
      );

      await messageRepo.deleteMessage(msg.id);

      final messages = await messageRepo.getThreadMessages(testThread.id);
      expect(messages, isEmpty);
    });

    test('getThreadMessages only returns messages for specified thread', () async {
      final thread2 = await threadRepo.createThread(
        userId: _userId,
        category: 'other',
        subject: 'Other Thread',
      );

      await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'Thread 1 message',
      );
      await messageRepo.addMessage(
        threadId: thread2.id,
        userId: _userId,
        message: 'Thread 2 message',
      );

      final thread1Messages = await messageRepo.getThreadMessages(testThread.id);
      expect(thread1Messages, hasLength(1));
      expect(thread1Messages.first.message, 'Thread 1 message');

      final thread2Messages = await messageRepo.getThreadMessages(thread2.id);
      expect(thread2Messages, hasLength(1));
      expect(thread2Messages.first.message, 'Thread 2 message');
    });

    test('watchThreadMessages emits updates reactively', () async {
      final stream = messageRepo.watchThreadMessages(testThread.id);

      // First emission: empty
      final first = await stream.first;
      expect(first, isEmpty);

      // Add a message
      await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'New message',
      );

      // Next emission should contain the message
      final second = await stream.first;
      expect(second, hasLength(1));
      expect(second.first.message, 'New message');
    });

    test('getMessageById returns message', () async {
      final created = await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'Find me',
      );

      final found = await messageRepo.getMessageById(created.id);
      expect(found, isNotNull);
      expect(found!.message, 'Find me');
    });

    test('getMessageById returns null for nonexistent', () async {
      final found = await messageRepo.getMessageById('nonexistent');
      expect(found, isNull);
    });

    test('deleteMessage soft deletes and creates oplog', () async {
      final msg = await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'Delete me',
      );

      await messageRepo.deleteMessage(msg.id);

      // Should not appear in non-deleted queries
      final messages = await messageRepo.getThreadMessages(testThread.id);
      expect(messages, isEmpty);

      // But should still exist in DB (soft delete)
      final raw = await messageRepo.getMessageById(msg.id);
      expect(raw, isNotNull);
      expect(raw!.isDeleted, true);
      expect(raw.version, 2);
    });

    test('deleteMessage throws for nonexistent message', () async {
      expect(
        () => messageRepo.deleteMessage('nonexistent'),
        throwsA(isA<FeedbackMessageNotFoundException>()),
      );
    });

    test('fieldUpdatedAt round-trips through DB correctly', () async {
      // Create a message and read it back
      final msg = await messageRepo.addMessage(
        threadId: testThread.id,
        userId: _userId,
        message: 'Field test',
      );

      // Read back from DB
      final fromDb = await messageRepo.getMessageById(msg.id);
      expect(fromDb, isNotNull);
      // fieldUpdatedAt starts empty for locally-created messages
      expect(fromDb!.fieldUpdatedAt, isEmpty);
    });
  });

  group('Cross-repository integration', () {
    test('thread with messages full lifecycle', () async {
      // Create thread
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'feature_request',
        subject: 'Add dark mode',
      );
      expect(thread.statusEnum, FeedbackStatus.open);

      // User sends first message
      final msg1 = await messageRepo.addMessage(
        threadId: thread.id,
        userId: _userId,
        message: 'Please add dark mode to the app',
      );
      expect(msg1.senderTypeEnum, FeedbackSenderType.user);

      // Simulate admin reply
      final msg2 = await messageRepo.addMessage(
        threadId: thread.id,
        userId: 'admin-user',
        message: 'We are working on it!',
        senderType: 'admin',
      );
      expect(msg2.isFromAdmin, true);

      // Update thread status
      final updated = await threadRepo.updateThread(
        id: thread.id,
        status: 'in_progress',
        adminAssigned: 'admin-user',
        lastMessageAt: msg2.createdAt,
      );
      expect(updated.statusEnum, FeedbackStatus.inProgress);
      expect(updated.adminAssigned, 'admin-user');

      // Verify message list
      final messages = await messageRepo.getThreadMessages(thread.id);
      expect(messages, hasLength(2));
      expect(messages.first.senderType, 'user');
      expect(messages.last.senderType, 'admin');

      // Resolve thread
      final resolved = await threadRepo.updateThread(
        id: thread.id,
        status: 'resolved',
      );
      expect(resolved.statusEnum, FeedbackStatus.resolved);
      expect(resolved.version, 3);

      // Verify all oplog entries were created
      final oplog = await db.getUnsyncedOps();
      final threadOps = oplog.where((o) => o.entityId == thread.id).toList();
      final messageOps = oplog.where(
        (o) => o.entityId == msg1.id || o.entityId == msg2.id,
      ).toList();

      // Thread: 1 insert + 2 updates = 3
      expect(threadOps, hasLength(3));
      // Messages: 2 inserts = 2
      expect(messageOps, hasLength(2));
    });

    test('soft deleting thread does not cascade to messages', () async {
      final thread = await threadRepo.createThread(
        userId: _userId,
        category: 'bug',
        subject: 'Cascade test',
      );

      await messageRepo.addMessage(
        threadId: thread.id,
        userId: _userId,
        message: 'Message 1',
      );
      await messageRepo.addMessage(
        threadId: thread.id,
        userId: _userId,
        message: 'Message 2',
      );

      // Delete thread
      await threadRepo.deleteThread(thread.id);

      // Thread should be soft deleted
      final deletedThread = await threadRepo.getThreadById(thread.id);
      expect(deletedThread!.isDeleted, true);

      // Messages should still be visible (no cascade)
      final messages = await messageRepo.getThreadMessages(thread.id);
      expect(messages, hasLength(2));
    });
  });
}
