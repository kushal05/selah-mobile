import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/feedback_thread_model.dart';

void main() {
  group('FeedbackThreadModel', () {
    test('constructor sets all fields', () {
      final thread = FeedbackThreadModel(
        id: 't-1',
        userId: 'test-user',
        category: 'bug',
        subject: 'App crashes on login',
        status: 'open',
        priority: 'high',
        lastMessageAt: 2000,
        adminAssigned: 'admin-1',
        unreadForUser: 3,
        unreadForAdmin: 1,
        deviceModel: 'Pixel 7',
        osVersion: 'Android 14',
        appVersion: '2.1.0',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
        fieldUpdatedAt: {'status': 1000},
      );

      expect(thread.id, 't-1');
      expect(thread.userId, 'test-user');
      expect(thread.category, 'bug');
      expect(thread.subject, 'App crashes on login');
      expect(thread.status, 'open');
      expect(thread.priority, 'high');
      expect(thread.lastMessageAt, 2000);
      expect(thread.adminAssigned, 'admin-1');
      expect(thread.unreadForUser, 3);
      expect(thread.unreadForAdmin, 1);
      expect(thread.deviceModel, 'Pixel 7');
      expect(thread.osVersion, 'Android 14');
      expect(thread.appVersion, '2.1.0');
      expect(thread.updatedAt, 1000);
      expect(thread.version, 1);
      expect(thread.deleted, 0);
      expect(thread.createdAt, 1000);
      expect(thread.fieldUpdatedAt, {'status': 1000});
    });

    test('constructor defaults for optional fields', () {
      final thread = FeedbackThreadModel(
        id: 't-1', userId: 'u', category: 'bug', subject: 'S',
        status: 'open', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(thread.priority, 'medium');
      expect(thread.unreadForUser, 0);
      expect(thread.unreadForAdmin, 0);
      expect(thread.deviceModel, isNull);
      expect(thread.osVersion, isNull);
      expect(thread.appVersion, isNull);
    });

    test('isDeleted returns correct values', () {
      final active = FeedbackThreadModel(
        id: 't-1', userId: 'u', category: 'bug', subject: 'S',
        status: 'open', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );
      final deleted = FeedbackThreadModel(
        id: 't-2', userId: 'u', category: 'bug', subject: 'S',
        status: 'open', updatedAt: 1000, version: 1, deleted: 1,
        createdAt: 1000,
      );

      expect(active.isDeleted, false);
      expect(deleted.isDeleted, true);
    });

    test('categoryEnum returns correct enum', () {
      final thread = FeedbackThreadModel(
        id: 't-1', userId: 'u', category: 'feature_request', subject: 'S',
        status: 'open', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(thread.categoryEnum, FeedbackCategory.featureRequest);
    });

    test('statusEnum returns correct enum', () {
      final thread = FeedbackThreadModel(
        id: 't-1', userId: 'u', category: 'bug', subject: 'S',
        status: 'in_progress', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(thread.statusEnum, FeedbackStatus.inProgress);
    });

    test('statusEnum handles waitingForUser', () {
      final thread = FeedbackThreadModel(
        id: 't-1', userId: 'u', category: 'bug', subject: 'S',
        status: 'waiting_for_user', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(thread.statusEnum, FeedbackStatus.waitingForUser);
    });

    test('priorityEnum returns correct enum', () {
      final thread = FeedbackThreadModel(
        id: 't-1', userId: 'u', category: 'bug', subject: 'S',
        status: 'open', priority: 'critical', updatedAt: 1000, version: 1,
        deleted: 0, createdAt: 1000,
      );

      expect(thread.priorityEnum, FeedbackPriority.critical);
    });

    test('isClosed returns true only for closed status', () {
      final open = FeedbackThreadModel(
        id: 't-1', userId: 'u', category: 'bug', subject: 'S',
        status: 'open', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );
      final closed = FeedbackThreadModel(
        id: 't-2', userId: 'u', category: 'bug', subject: 'S',
        status: 'closed', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(open.isClosed, false);
      expect(closed.isClosed, true);
    });

    test('hasUnread returns true when unreadForUser > 0', () {
      final noUnread = FeedbackThreadModel(
        id: 't-1', userId: 'u', category: 'bug', subject: 'S',
        status: 'open', unreadForUser: 0, updatedAt: 1000, version: 1,
        deleted: 0, createdAt: 1000,
      );
      final hasUnread = FeedbackThreadModel(
        id: 't-2', userId: 'u', category: 'bug', subject: 'S',
        status: 'open', unreadForUser: 2, updatedAt: 1000, version: 1,
        deleted: 0, createdAt: 1000,
      );

      expect(noUnread.hasUnread, false);
      expect(hasUnread.hasUnread, true);
    });

    group('create factory', () {
      test('defaults are correct', () {
        final thread = FeedbackThreadModel.create(
          id: 't-new',
          userId: 'test-user',
          category: 'bug',
          subject: 'New Thread',
        );

        expect(thread.id, 't-new');
        expect(thread.userId, 'test-user');
        expect(thread.category, 'bug');
        expect(thread.subject, 'New Thread');
        expect(thread.status, 'open');
        expect(thread.priority, 'medium');
        expect(thread.lastMessageAt, isNotNull);
        expect(thread.adminAssigned, isNull);
        expect(thread.unreadForAdmin, 1);
        expect(thread.unreadForUser, 0);
        expect(thread.deviceModel, isNull);
        expect(thread.osVersion, isNull);
        expect(thread.appVersion, isNull);
        expect(thread.version, 1);
        expect(thread.deleted, 0);
        expect(thread.createdAt, thread.updatedAt);
      });

      test('accepts device metadata', () {
        final thread = FeedbackThreadModel.create(
          id: 't-dev',
          userId: 'test-user',
          category: 'bug',
          subject: 'With Device Info',
          deviceModel: 'Pixel 7',
          osVersion: 'Android 14',
          appVersion: '2.0.0',
        );

        expect(thread.deviceModel, 'Pixel 7');
        expect(thread.osVersion, 'Android 14');
        expect(thread.appVersion, '2.0.0');
      });
    });

    group('toJson / fromJson round-trip', () {
      test('round-trip preserves all fields', () {
        final original = FeedbackThreadModel(
          id: 't-rt',
          userId: 'test-user',
          category: 'ui_issue',
          subject: 'Round Trip',
          status: 'resolved',
          priority: 'high',
          lastMessageAt: 2000,
          adminAssigned: 'admin-1',
          unreadForUser: 5,
          unreadForAdmin: 2,
          deviceModel: 'iPhone 15',
          osVersion: 'iOS 17.2',
          appVersion: '1.5.0',
          updatedAt: 1500,
          version: 3,
          deleted: 0,
          createdAt: 1000,
          fieldUpdatedAt: {'status': 1500, 'adminAssigned': 1200},
        );

        final json = original.toJson();
        final restored = FeedbackThreadModel.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.userId, original.userId);
        expect(restored.category, original.category);
        expect(restored.subject, original.subject);
        expect(restored.status, original.status);
        expect(restored.priority, original.priority);
        expect(restored.lastMessageAt, original.lastMessageAt);
        expect(restored.adminAssigned, original.adminAssigned);
        expect(restored.unreadForUser, original.unreadForUser);
        expect(restored.unreadForAdmin, original.unreadForAdmin);
        expect(restored.deviceModel, original.deviceModel);
        expect(restored.osVersion, original.osVersion);
        expect(restored.appVersion, original.appVersion);
        expect(restored.updatedAt, original.updatedAt);
        expect(restored.version, original.version);
        expect(restored.deleted, original.deleted);
        expect(restored.createdAt, original.createdAt);
        expect(restored.fieldUpdatedAt, original.fieldUpdatedAt);
      });

      test('fromJson defaults status to open', () {
        final json = {
          'id': 't-1',
          'userId': 'u',
          'category': 'bug',
          'subject': 'S',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final thread = FeedbackThreadModel.fromJson(json);
        expect(thread.status, 'open');
      });

      test('fromJson defaults priority to medium', () {
        final json = {
          'id': 't-1',
          'userId': 'u',
          'category': 'bug',
          'subject': 'S',
          'status': 'open',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final thread = FeedbackThreadModel.fromJson(json);
        expect(thread.priority, 'medium');
      });

      test('fromJson handles _id normalization', () {
        final json = {
          '_id': 't-mongo',
          'userId': 'u',
          'category': 'bug',
          'subject': 'S',
          'status': 'open',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final thread = FeedbackThreadModel.fromJson(json);
        expect(thread.id, 't-mongo');
      });

      test('fromJson handles boolean deleted', () {
        final json = {
          'id': 't-1',
          'userId': 'u',
          'category': 'bug',
          'subject': 'S',
          'status': 'open',
          'updatedAt': 1000,
          'version': 1,
          'deleted': true,
          'createdAt': 1000,
        };

        final thread = FeedbackThreadModel.fromJson(json);
        expect(thread.deleted, 1);
      });

      test('fromJson defaults deleted to 0', () {
        final json = {
          'id': 't-1',
          'userId': 'u',
          'category': 'bug',
          'subject': 'S',
          'status': 'open',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final thread = FeedbackThreadModel.fromJson(json);
        expect(thread.deleted, 0);
      });

      test('fromJson handles missing fieldUpdatedAt', () {
        final json = {
          'id': 't-1',
          'userId': 'u',
          'category': 'bug',
          'subject': 'S',
          'status': 'open',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final thread = FeedbackThreadModel.fromJson(json);
        expect(thread.fieldUpdatedAt, isEmpty);
      });

      test('fromJson defaults unread counts to 0', () {
        final json = {
          'id': 't-1',
          'userId': 'u',
          'category': 'bug',
          'subject': 'S',
          'status': 'open',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final thread = FeedbackThreadModel.fromJson(json);
        expect(thread.unreadForUser, 0);
        expect(thread.unreadForAdmin, 0);
      });
    });

    group('copyWithUpdate', () {
      final original = FeedbackThreadModel(
        id: 't-1',
        userId: 'test-user',
        category: 'bug',
        subject: 'Original',
        status: 'open',
        lastMessageAt: 1000,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );

      test('updates status and increments version', () {
        final updated = original.copyWithUpdate(status: 'in_progress');
        expect(updated.status, 'in_progress');
        expect(updated.version, 2);
        expect(updated.subject, original.subject);
      });

      test('updates lastMessageAt', () {
        final updated = original.copyWithUpdate(lastMessageAt: 5000);
        expect(updated.lastMessageAt, 5000);
        expect(updated.version, 2);
      });

      test('updates adminAssigned', () {
        final updated = original.copyWithUpdate(adminAssigned: 'admin-1');
        expect(updated.adminAssigned, 'admin-1');
        expect(updated.version, 2);
      });

      test('updates priority', () {
        final updated = original.copyWithUpdate(priority: 'critical');
        expect(updated.priority, 'critical');
        expect(updated.version, 2);
      });

      test('updates unread counts', () {
        final updated = original.copyWithUpdate(
          unreadForUser: 3,
          unreadForAdmin: 0,
        );
        expect(updated.unreadForUser, 3);
        expect(updated.unreadForAdmin, 0);
        expect(updated.version, 2);
      });

      test('preserves all fields when nothing specified', () {
        final updated = original.copyWithUpdate();
        expect(updated.status, original.status);
        expect(updated.lastMessageAt, original.lastMessageAt);
        expect(updated.adminAssigned, original.adminAssigned);
        expect(updated.priority, original.priority);
        expect(updated.version, 2);
      });
    });

    group('softDelete', () {
      test('sets deleted to 1 and increments version', () {
        final thread = FeedbackThreadModel.create(
          id: 't-1',
          userId: 'test-user',
          category: 'bug',
          subject: 'Test',
        );

        final deleted = thread.softDelete();
        expect(deleted.isDeleted, true);
        expect(deleted.deleted, 1);
        expect(deleted.version, 2);
        expect(deleted.id, thread.id);
        expect(deleted.subject, thread.subject);
      });

      test('preserves device metadata after softDelete', () {
        final thread = FeedbackThreadModel.create(
          id: 't-1',
          userId: 'test-user',
          category: 'bug',
          subject: 'Test',
          deviceModel: 'Pixel 7',
          osVersion: 'Android 14',
          appVersion: '2.0.0',
        );

        final deleted = thread.softDelete();
        expect(deleted.deviceModel, 'Pixel 7');
        expect(deleted.osVersion, 'Android 14');
        expect(deleted.appVersion, '2.0.0');
      });
    });

    group('equality', () {
      test('equal when same id and version', () {
        final a = FeedbackThreadModel(
          id: 't-1', userId: 'u', category: 'bug', subject: 'A',
          status: 'open', updatedAt: 1000, version: 1, deleted: 0,
          createdAt: 1000,
        );
        final b = FeedbackThreadModel(
          id: 't-1', userId: 'u', category: 'performance', subject: 'B',
          status: 'closed', updatedAt: 2000, version: 1, deleted: 0,
          createdAt: 500,
        );

        expect(a, equals(b));
      });

      test('not equal when different version', () {
        final a = FeedbackThreadModel(
          id: 't-1', userId: 'u', category: 'bug', subject: 'A',
          status: 'open', updatedAt: 1000, version: 1, deleted: 0,
          createdAt: 1000,
        );
        final b = FeedbackThreadModel(
          id: 't-1', userId: 'u', category: 'bug', subject: 'A',
          status: 'open', updatedAt: 1000, version: 2, deleted: 0,
          createdAt: 1000,
        );

        expect(a, isNot(equals(b)));
      });
    });

    test('toString contains key info', () {
      final thread = FeedbackThreadModel(
        id: 't-ts', userId: 'u', category: 'bug', subject: 'Test Thread',
        status: 'open', updatedAt: 1000, version: 2, deleted: 0,
        createdAt: 1000,
      );

      final str = thread.toString();
      expect(str, contains('t-ts'));
      expect(str, contains('Test Thread'));
      expect(str, contains('open'));
      expect(str, contains('v2'));
    });
  });

  group('FeedbackCategory', () {
    test('toDbValue returns correct strings', () {
      expect(FeedbackCategory.bug.toDbValue(), 'bug');
      expect(FeedbackCategory.featureRequest.toDbValue(), 'feature_request');
      expect(FeedbackCategory.uiIssue.toDbValue(), 'ui_issue');
      expect(FeedbackCategory.performance.toDbValue(), 'performance');
      expect(FeedbackCategory.account.toDbValue(), 'account');
      expect(FeedbackCategory.content.toDbValue(), 'content');
      expect(FeedbackCategory.other.toDbValue(), 'other');
    });

    test('fromDbValue returns correct enums', () {
      expect(FeedbackCategory.fromDbValue('bug'), FeedbackCategory.bug);
      expect(FeedbackCategory.fromDbValue('feature_request'), FeedbackCategory.featureRequest);
      expect(FeedbackCategory.fromDbValue('ui_issue'), FeedbackCategory.uiIssue);
      expect(FeedbackCategory.fromDbValue('performance'), FeedbackCategory.performance);
      expect(FeedbackCategory.fromDbValue('account'), FeedbackCategory.account);
      expect(FeedbackCategory.fromDbValue('content'), FeedbackCategory.content);
      expect(FeedbackCategory.fromDbValue('other'), FeedbackCategory.other);
    });

    test('fromDbValue defaults to other for unknown', () {
      expect(FeedbackCategory.fromDbValue('unknown'), FeedbackCategory.other);
    });

    test('displayName returns correct values', () {
      expect(FeedbackCategory.bug.displayName, 'Bug');
      expect(FeedbackCategory.featureRequest.displayName, 'Feature Request');
      expect(FeedbackCategory.uiIssue.displayName, 'UI Issue');
      expect(FeedbackCategory.performance.displayName, 'Performance');
      expect(FeedbackCategory.account.displayName, 'Account');
      expect(FeedbackCategory.content.displayName, 'Content');
      expect(FeedbackCategory.other.displayName, 'Other');
    });
  });

  group('FeedbackStatus', () {
    test('toDbValue returns correct strings', () {
      expect(FeedbackStatus.open.toDbValue(), 'open');
      expect(FeedbackStatus.inProgress.toDbValue(), 'in_progress');
      expect(FeedbackStatus.waitingForUser.toDbValue(), 'waiting_for_user');
      expect(FeedbackStatus.resolved.toDbValue(), 'resolved');
      expect(FeedbackStatus.closed.toDbValue(), 'closed');
    });

    test('fromDbValue returns correct enums', () {
      expect(FeedbackStatus.fromDbValue('open'), FeedbackStatus.open);
      expect(FeedbackStatus.fromDbValue('in_progress'), FeedbackStatus.inProgress);
      expect(FeedbackStatus.fromDbValue('waiting_for_user'), FeedbackStatus.waitingForUser);
      expect(FeedbackStatus.fromDbValue('resolved'), FeedbackStatus.resolved);
      expect(FeedbackStatus.fromDbValue('closed'), FeedbackStatus.closed);
    });

    test('fromDbValue defaults to open for unknown', () {
      expect(FeedbackStatus.fromDbValue('unknown'), FeedbackStatus.open);
    });

    test('displayName returns correct values', () {
      expect(FeedbackStatus.open.displayName, 'Open');
      expect(FeedbackStatus.inProgress.displayName, 'In Progress');
      expect(FeedbackStatus.waitingForUser.displayName, 'Waiting for You');
      expect(FeedbackStatus.resolved.displayName, 'Resolved');
      expect(FeedbackStatus.closed.displayName, 'Closed');
    });
  });

  group('FeedbackPriority', () {
    test('toDbValue returns correct strings', () {
      expect(FeedbackPriority.low.toDbValue(), 'low');
      expect(FeedbackPriority.medium.toDbValue(), 'medium');
      expect(FeedbackPriority.high.toDbValue(), 'high');
      expect(FeedbackPriority.critical.toDbValue(), 'critical');
    });

    test('fromDbValue returns correct enums', () {
      expect(FeedbackPriority.fromDbValue('low'), FeedbackPriority.low);
      expect(FeedbackPriority.fromDbValue('medium'), FeedbackPriority.medium);
      expect(FeedbackPriority.fromDbValue('high'), FeedbackPriority.high);
      expect(FeedbackPriority.fromDbValue('critical'), FeedbackPriority.critical);
    });

    test('fromDbValue defaults to medium for unknown', () {
      expect(FeedbackPriority.fromDbValue('unknown'), FeedbackPriority.medium);
    });

    test('displayName returns correct values', () {
      expect(FeedbackPriority.low.displayName, 'Low');
      expect(FeedbackPriority.medium.displayName, 'Medium');
      expect(FeedbackPriority.high.displayName, 'High');
      expect(FeedbackPriority.critical.displayName, 'Critical');
    });
  });
}
