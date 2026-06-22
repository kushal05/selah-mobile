import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/feedback_attachment_model.dart';

void main() {
  group('FeedbackAttachmentModel', () {
    test('constructor sets all fields', () {
      final attachment = FeedbackAttachmentModel(
        id: 'a-1',
        messageId: 'm-1',
        url: 'https://cdn.example.com/file.png',
        type: 'image',
        size: 102400,
        fileName: 'screenshot.png',
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
        fieldUpdatedAt: {'url': 1000},
      );

      expect(attachment.id, 'a-1');
      expect(attachment.messageId, 'm-1');
      expect(attachment.url, 'https://cdn.example.com/file.png');
      expect(attachment.type, 'image');
      expect(attachment.size, 102400);
      expect(attachment.fileName, 'screenshot.png');
      expect(attachment.updatedAt, 1000);
      expect(attachment.version, 1);
      expect(attachment.deleted, 0);
      expect(attachment.createdAt, 1000);
      expect(attachment.fieldUpdatedAt, {'url': 1000});
    });

    test('defaults for optional fields', () {
      final attachment = FeedbackAttachmentModel(
        id: 'a-1', messageId: 'm-1', url: 'https://example.com/f',
        type: 'file', updatedAt: 1000, version: 1, deleted: 0,
        createdAt: 1000,
      );

      expect(attachment.size, 0);
      expect(attachment.fileName, isNull);
    });

    test('isDeleted returns correct values', () {
      final active = FeedbackAttachmentModel(
        id: 'a-1', messageId: 'm-1', url: 'u', type: 'file',
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );
      final deleted = FeedbackAttachmentModel(
        id: 'a-2', messageId: 'm-1', url: 'u', type: 'file',
        updatedAt: 1000, version: 1, deleted: 1, createdAt: 1000,
      );

      expect(active.isDeleted, false);
      expect(deleted.isDeleted, true);
    });

    test('typeEnum returns correct enum', () {
      final image = FeedbackAttachmentModel(
        id: 'a-1', messageId: 'm-1', url: 'u', type: 'image',
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );
      final video = FeedbackAttachmentModel(
        id: 'a-2', messageId: 'm-1', url: 'u', type: 'video',
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );
      final file = FeedbackAttachmentModel(
        id: 'a-3', messageId: 'm-1', url: 'u', type: 'file',
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );

      expect(image.typeEnum, FeedbackAttachmentType.image);
      expect(video.typeEnum, FeedbackAttachmentType.video);
      expect(file.typeEnum, FeedbackAttachmentType.file);
    });

    test('isImage and isVideo return correct values', () {
      final image = FeedbackAttachmentModel(
        id: 'a-1', messageId: 'm-1', url: 'u', type: 'image',
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );
      final video = FeedbackAttachmentModel(
        id: 'a-2', messageId: 'm-1', url: 'u', type: 'video',
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );
      final file = FeedbackAttachmentModel(
        id: 'a-3', messageId: 'm-1', url: 'u', type: 'file',
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );

      expect(image.isImage, true);
      expect(image.isVideo, false);
      expect(video.isImage, false);
      expect(video.isVideo, true);
      expect(file.isImage, false);
      expect(file.isVideo, false);
    });

    group('create factory', () {
      test('defaults are correct', () {
        final a = FeedbackAttachmentModel.create(
          id: 'a-new',
          messageId: 'm-1',
          url: 'https://cdn.example.com/file.pdf',
          type: 'file',
        );

        expect(a.id, 'a-new');
        expect(a.messageId, 'm-1');
        expect(a.url, 'https://cdn.example.com/file.pdf');
        expect(a.type, 'file');
        expect(a.size, 0);
        expect(a.fileName, isNull);
        expect(a.version, 1);
        expect(a.deleted, 0);
        expect(a.createdAt, a.updatedAt);
      });

      test('accepts optional fields', () {
        final a = FeedbackAttachmentModel.create(
          id: 'a-new',
          messageId: 'm-1',
          url: 'https://cdn.example.com/photo.jpg',
          type: 'image',
          size: 204800,
          fileName: 'photo.jpg',
        );

        expect(a.size, 204800);
        expect(a.fileName, 'photo.jpg');
      });
    });

    group('toJson / fromJson round-trip', () {
      test('round-trip preserves all fields', () {
        final original = FeedbackAttachmentModel(
          id: 'a-rt',
          messageId: 'm-1',
          url: 'https://cdn.example.com/doc.pdf',
          type: 'file',
          size: 512000,
          fileName: 'report.pdf',
          updatedAt: 1500,
          version: 2,
          deleted: 0,
          createdAt: 1000,
          fieldUpdatedAt: {'url': 1500},
        );

        final json = original.toJson();
        final restored = FeedbackAttachmentModel.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.messageId, original.messageId);
        expect(restored.url, original.url);
        expect(restored.type, original.type);
        expect(restored.size, original.size);
        expect(restored.fileName, original.fileName);
        expect(restored.updatedAt, original.updatedAt);
        expect(restored.version, original.version);
        expect(restored.deleted, original.deleted);
        expect(restored.createdAt, original.createdAt);
        expect(restored.fieldUpdatedAt, original.fieldUpdatedAt);
      });

      test('fromJson handles _id normalization', () {
        final json = {
          '_id': 'a-mongo',
          'messageId': 'm-1',
          'url': 'https://example.com/f',
          'type': 'file',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final a = FeedbackAttachmentModel.fromJson(json);
        expect(a.id, 'a-mongo');
      });

      test('fromJson defaults type to file', () {
        final json = {
          'id': 'a-1',
          'messageId': 'm-1',
          'url': 'https://example.com/f',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final a = FeedbackAttachmentModel.fromJson(json);
        expect(a.type, 'file');
      });

      test('fromJson defaults size to 0', () {
        final json = {
          'id': 'a-1',
          'messageId': 'm-1',
          'url': 'https://example.com/f',
          'type': 'image',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final a = FeedbackAttachmentModel.fromJson(json);
        expect(a.size, 0);
      });

      test('fromJson handles boolean deleted', () {
        final json = {
          'id': 'a-1',
          'messageId': 'm-1',
          'url': 'u',
          'type': 'file',
          'updatedAt': 1000,
          'version': 1,
          'deleted': true,
          'createdAt': 1000,
        };

        final a = FeedbackAttachmentModel.fromJson(json);
        expect(a.deleted, 1);
      });

      test('fromJson defaults deleted to 0', () {
        final json = {
          'id': 'a-1',
          'messageId': 'm-1',
          'url': 'u',
          'type': 'file',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final a = FeedbackAttachmentModel.fromJson(json);
        expect(a.deleted, 0);
      });

      test('fromJson handles missing fieldUpdatedAt', () {
        final json = {
          'id': 'a-1',
          'messageId': 'm-1',
          'url': 'u',
          'type': 'file',
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final a = FeedbackAttachmentModel.fromJson(json);
        expect(a.fieldUpdatedAt, isEmpty);
      });
    });

    group('softDelete', () {
      test('sets deleted to 1 and increments version', () {
        final a = FeedbackAttachmentModel.create(
          id: 'a-1',
          messageId: 'm-1',
          url: 'https://example.com/f',
          type: 'image',
        );

        final deleted = a.softDelete();
        expect(deleted.isDeleted, true);
        expect(deleted.deleted, 1);
        expect(deleted.version, 2);
        expect(deleted.id, a.id);
        expect(deleted.url, a.url);
      });
    });

    group('equality', () {
      test('equal when same id and version', () {
        final a = FeedbackAttachmentModel(
          id: 'a-1', messageId: 'm-1', url: 'u1', type: 'image',
          updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
        );
        final b = FeedbackAttachmentModel(
          id: 'a-1', messageId: 'm-2', url: 'u2', type: 'video',
          updatedAt: 2000, version: 1, deleted: 0, createdAt: 500,
        );

        expect(a, equals(b));
      });

      test('not equal when different version', () {
        final a = FeedbackAttachmentModel(
          id: 'a-1', messageId: 'm-1', url: 'u', type: 'file',
          updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
        );
        final b = FeedbackAttachmentModel(
          id: 'a-1', messageId: 'm-1', url: 'u', type: 'file',
          updatedAt: 1000, version: 2, deleted: 0, createdAt: 1000,
        );

        expect(a, isNot(equals(b)));
      });
    });

    test('toString contains key info', () {
      final a = FeedbackAttachmentModel(
        id: 'a-ts', messageId: 'm-1', url: 'u', type: 'image',
        updatedAt: 1000, version: 2, deleted: 0, createdAt: 1000,
      );

      final str = a.toString();
      expect(str, contains('a-ts'));
      expect(str, contains('m-1'));
      expect(str, contains('image'));
      expect(str, contains('v2'));
    });
  });

  group('FeedbackAttachmentType', () {
    test('toDbValue returns correct strings', () {
      expect(FeedbackAttachmentType.image.toDbValue(), 'image');
      expect(FeedbackAttachmentType.video.toDbValue(), 'video');
      expect(FeedbackAttachmentType.file.toDbValue(), 'file');
    });

    test('fromDbValue returns correct enums', () {
      expect(FeedbackAttachmentType.fromDbValue('image'), FeedbackAttachmentType.image);
      expect(FeedbackAttachmentType.fromDbValue('video'), FeedbackAttachmentType.video);
      expect(FeedbackAttachmentType.fromDbValue('file'), FeedbackAttachmentType.file);
    });

    test('fromDbValue defaults to file for unknown', () {
      expect(FeedbackAttachmentType.fromDbValue('unknown'), FeedbackAttachmentType.file);
    });
  });
}
