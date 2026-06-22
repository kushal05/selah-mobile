import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/feedback_message_model.dart';

void main() {
  group('FeedbackMessageModel', () {
    test('constructor sets all fields', () {
      final msg = FeedbackMessageModel(
        id: 'm-1',
        threadId: 't-1',
        userId: 'test-user',
        message: 'Hello support',
        senderType: 'user',
        hasAttachments: 1,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
        fieldUpdatedAt: {'message': 1000},
      );

      expect(msg.id, 'm-1');
      expect(msg.threadId, 't-1');
      expect(msg.userId, 'test-user');
      expect(msg.message, 'Hello support');
      expect(msg.senderType, 'user');
      expect(msg.hasAttachments, 1);
      expect(msg.updatedAt, 1000);
      expect(msg.version, 1);
      expect(msg.deleted, 0);
      expect(msg.createdAt, 1000);
      expect(msg.fieldUpdatedAt, {'message': 1000});
    });

    test('hasAttachments defaults to 0', () {
      final msg = FeedbackMessageModel(
        id: 'm-1', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'user', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(msg.hasAttachments, 0);
      expect(msg.hasFiles, false);
    });

    test('isDeleted returns correct values', () {
      final active = FeedbackMessageModel(
        id: 'm-1', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'user', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );
      final deleted = FeedbackMessageModel(
        id: 'm-2', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'user', updatedAt: 1000, version: 1, deleted: 1,
        createdAt: 1000,
      );

      expect(active.isDeleted, false);
      expect(deleted.isDeleted, true);
    });

    test('senderTypeEnum returns correct enum', () {
      final userMsg = FeedbackMessageModel(
        id: 'm-1', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'user', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );
      final adminMsg = FeedbackMessageModel(
        id: 'm-2', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'admin', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );
      final systemMsg = FeedbackMessageModel(
        id: 'm-3', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'system', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(userMsg.senderTypeEnum, FeedbackSenderType.user);
      expect(adminMsg.senderTypeEnum, FeedbackSenderType.admin);
      expect(systemMsg.senderTypeEnum, FeedbackSenderType.system);
    });

    test('isFromAdmin returns correct values', () {
      final userMsg = FeedbackMessageModel(
        id: 'm-1', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'user', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );
      final adminMsg = FeedbackMessageModel(
        id: 'm-2', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'admin', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(userMsg.isFromAdmin, false);
      expect(adminMsg.isFromAdmin, true);
    });

    test('isSystemMessage returns correct values', () {
      final userMsg = FeedbackMessageModel(
        id: 'm-1', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'user', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );
      final systemMsg = FeedbackMessageModel(
        id: 'm-2', threadId: 't-1', userId: 'u', message: 'Status changed',
        senderType: 'system', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(userMsg.isSystemMessage, false);
      expect(systemMsg.isSystemMessage, true);
    });

    test('hasFiles returns correct values', () {
      final noFiles = FeedbackMessageModel(
        id: 'm-1', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'user', hasAttachments: 0, updatedAt: 1000, version: 1,
        deleted: 0, createdAt: 1000,
      );
      final withFiles = FeedbackMessageModel(
        id: 'm-2', threadId: 't-1', userId: 'u', message: 'M',
        senderType: 'user', hasAttachments: 1, updatedAt: 1000, version: 1,
        deleted: 0, createdAt: 1000,
      );

      expect(noFiles.hasFiles, false);
      expect(withFiles.hasFiles, true);
    });

    group('create factory', () {
      test('defaults are correct', () {
        final msg = FeedbackMessageModel.create(
          id: 'm-new',
          threadId: 't-1',
          userId: 'test-user',
          message: 'New message',
        );

        expect(msg.id, 'm-new');
        expect(msg.threadId, 't-1');
        expect(msg.userId, 'test-user');
        expect(msg.message, 'New message');
        expect(msg.senderType, 'user');
        expect(msg.hasAttachments, 0);
        expect(msg.version, 1);
        expect(msg.deleted, 0);
        expect(msg.createdAt, msg.updatedAt);
      });

      test('accepts custom senderType', () {
        final msg = FeedbackMessageModel.create(
          id: 'm-admin',
          threadId: 't-1',
          userId: 'admin-user',
          message: 'Admin reply',
          senderType: 'admin',
        );

        expect(msg.senderType, 'admin');
        expect(msg.isFromAdmin, true);
      });

      test('accepts system senderType', () {
        final msg = FeedbackMessageModel.create(
          id: 'm-sys',
          threadId: 't-1',
          userId: 'system',
          message: 'Thread marked as resolved',
          senderType: 'system',
        );

        expect(msg.senderType, 'system');
        expect(msg.isSystemMessage, true);
      });

      test('accepts hasAttachments', () {
        final msg = FeedbackMessageModel.create(
          id: 'm-att',
          threadId: 't-1',
          userId: 'test-user',
          message: 'See attached',
          hasAttachments: 1,
        );

        expect(msg.hasAttachments, 1);
        expect(msg.hasFiles, true);
      });
    });

    group('toJson / fromJson round-trip', () {
      test('round-trip preserves all fields', () {
        final original = FeedbackMessageModel(
          id: 'm-rt',
          threadId: 't-1',
          userId: 'test-user',
          message: 'Round trip test',
          senderType: 'admin',
          hasAttachments: 1,
          updatedAt: 1500,
          version: 3,
          deleted: 0,
          createdAt: 1000,
          fieldUpdatedAt: {'message': 1500},
        );

        final json = original.toJson();
        final restored = FeedbackMessageModel.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.threadId, original.threadId);
        expect(restored.userId, original.userId);
        expect(restored.message, original.message);
        expect(restored.senderType, original.senderType);
        expect(restored.hasAttachments, original.hasAttachments);
        expect(restored.updatedAt, original.updatedAt);
        expect(restored.version, original.version);
        expect(restored.deleted, original.deleted);
        expect(restored.createdAt, original.createdAt);
        expect(restored.fieldUpdatedAt, original.fieldUpdatedAt);
      });

      test('fromJson defaults senderType to user', () {
        final json = {
          'id': 'm-1',
          'threadId': 't-1',
          'userId': 'u',
          'message': 'M',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final msg = FeedbackMessageModel.fromJson(json);
        expect(msg.senderType, 'user');
      });

      test('fromJson defaults hasAttachments to 0', () {
        final json = {
          'id': 'm-1',
          'threadId': 't-1',
          'userId': 'u',
          'message': 'M',
          'senderType': 'user',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final msg = FeedbackMessageModel.fromJson(json);
        expect(msg.hasAttachments, 0);
      });

      test('fromJson handles _id normalization', () {
        final json = {
          '_id': 'm-mongo',
          'threadId': 't-1',
          'userId': 'u',
          'message': 'M',
          'senderType': 'user',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final msg = FeedbackMessageModel.fromJson(json);
        expect(msg.id, 'm-mongo');
      });

      test('fromJson handles boolean deleted', () {
        final json = {
          'id': 'm-1',
          'threadId': 't-1',
          'userId': 'u',
          'message': 'M',
          'senderType': 'user',
          'updatedAt': 1000,
          'version': 1,
          'deleted': true,
          'createdAt': 1000,
        };

        final msg = FeedbackMessageModel.fromJson(json);
        expect(msg.deleted, 1);
      });

      test('fromJson defaults deleted to 0', () {
        final json = {
          'id': 'm-1',
          'threadId': 't-1',
          'userId': 'u',
          'message': 'M',
          'senderType': 'user',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final msg = FeedbackMessageModel.fromJson(json);
        expect(msg.deleted, 0);
      });

      test('fromJson handles missing fieldUpdatedAt', () {
        final json = {
          'id': 'm-1',
          'threadId': 't-1',
          'userId': 'u',
          'message': 'M',
          'senderType': 'user',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final msg = FeedbackMessageModel.fromJson(json);
        expect(msg.fieldUpdatedAt, isEmpty);
      });
    });

    group('copyWithUpdate', () {
      final original = FeedbackMessageModel(
        id: 'm-1',
        threadId: 't-1',
        userId: 'test-user',
        message: 'Original',
        senderType: 'user',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );

      test('updates message and increments version', () {
        final updated = original.copyWithUpdate(message: 'Updated message');
        expect(updated.message, 'Updated message');
        expect(updated.version, 2);
        expect(updated.threadId, original.threadId);
      });

      test('updates hasAttachments', () {
        final updated = original.copyWithUpdate(hasAttachments: 1);
        expect(updated.hasAttachments, 1);
        expect(updated.hasFiles, true);
        expect(updated.version, 2);
      });

      test('preserves all fields when nothing specified', () {
        final updated = original.copyWithUpdate();
        expect(updated.message, original.message);
        expect(updated.hasAttachments, original.hasAttachments);
        expect(updated.version, 2);
      });
    });

    group('softDelete', () {
      test('sets deleted to 1 and increments version', () {
        final msg = FeedbackMessageModel.create(
          id: 'm-1',
          threadId: 't-1',
          userId: 'test-user',
          message: 'Test',
        );

        final deleted = msg.softDelete();
        expect(deleted.isDeleted, true);
        expect(deleted.deleted, 1);
        expect(deleted.version, 2);
        expect(deleted.id, msg.id);
        expect(deleted.message, msg.message);
      });

      test('preserves hasAttachments after softDelete', () {
        final msg = FeedbackMessageModel.create(
          id: 'm-1',
          threadId: 't-1',
          userId: 'test-user',
          message: 'Test',
          hasAttachments: 1,
        );

        final deleted = msg.softDelete();
        expect(deleted.hasAttachments, 1);
      });
    });

    group('equality', () {
      test('equal when same id and version', () {
        final a = FeedbackMessageModel(
          id: 'm-1', threadId: 't-1', userId: 'u', message: 'A',
          senderType: 'user', updatedAt: 1000, version: 1, deleted: 0,
          createdAt: 1000,
        );
        final b = FeedbackMessageModel(
          id: 'm-1', threadId: 't-2', userId: 'v', message: 'B',
          senderType: 'admin', updatedAt: 2000, version: 1, deleted: 0,
          createdAt: 500,
        );

        expect(a, equals(b));
      });

      test('not equal when different version', () {
        final a = FeedbackMessageModel(
          id: 'm-1', threadId: 't-1', userId: 'u', message: 'A',
          senderType: 'user', updatedAt: 1000, version: 1, deleted: 0,
          createdAt: 1000,
        );
        final b = FeedbackMessageModel(
          id: 'm-1', threadId: 't-1', userId: 'u', message: 'A',
          senderType: 'user', updatedAt: 1000, version: 2, deleted: 0,
          createdAt: 1000,
        );

        expect(a, isNot(equals(b)));
      });
    });

    test('toString contains key info', () {
      final msg = FeedbackMessageModel(
        id: 'm-ts', threadId: 't-1', userId: 'u', message: 'Test',
        senderType: 'admin', updatedAt: 1000, version: 2, deleted: 0,
        createdAt: 1000,
      );

      final str = msg.toString();
      expect(str, contains('m-ts'));
      expect(str, contains('t-1'));
      expect(str, contains('admin'));
      expect(str, contains('v2'));
    });
  });

  group('FeedbackSenderType', () {
    test('toDbValue returns correct strings', () {
      expect(FeedbackSenderType.user.toDbValue(), 'user');
      expect(FeedbackSenderType.admin.toDbValue(), 'admin');
      expect(FeedbackSenderType.system.toDbValue(), 'system');
    });

    test('fromDbValue returns correct enums', () {
      expect(FeedbackSenderType.fromDbValue('user'), FeedbackSenderType.user);
      expect(FeedbackSenderType.fromDbValue('admin'), FeedbackSenderType.admin);
      expect(FeedbackSenderType.fromDbValue('system'), FeedbackSenderType.system);
    });

    test('fromDbValue defaults to user for unknown', () {
      expect(FeedbackSenderType.fromDbValue('unknown'), FeedbackSenderType.user);
    });
  });
}
