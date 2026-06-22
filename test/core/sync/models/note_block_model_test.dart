import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/note_block_model.dart';

void main() {
  group('BlockType', () {
    test('toDbValue returns enum name', () {
      expect(BlockType.paragraph.toDbValue(), 'paragraph');
      expect(BlockType.heading1.toDbValue(), 'heading1');
      expect(BlockType.heading2.toDbValue(), 'heading2');
      expect(BlockType.heading3.toDbValue(), 'heading3');
      expect(BlockType.bulletList.toDbValue(), 'bulletList');
      expect(BlockType.numberedList.toDbValue(), 'numberedList');
      expect(BlockType.checkbox.toDbValue(), 'checkbox');
      expect(BlockType.quote.toDbValue(), 'quote');
      expect(BlockType.code.toDbValue(), 'code');
      expect(BlockType.divider.toDbValue(), 'divider');
      expect(BlockType.image.toDbValue(), 'image');
    });

    test('fromDbValue round-trips all values', () {
      for (final type in BlockType.values) {
        expect(BlockType.fromDbValue(type.toDbValue()), type);
      }
    });

    test('fromDbValue defaults to paragraph for unknown', () {
      expect(BlockType.fromDbValue('unknown'), BlockType.paragraph);
    });
  });

  group('NoteBlockModel', () {
    test('plainText extracts text from text key', () {
      final block = NoteBlockModel(
        id: 'b-1',
        noteId: 'n-1',
        blockType: BlockType.paragraph,
        content: {'text': 'Hello world'},
        orderIndex: 0,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(block.plainText, 'Hello world');
    });

    test('plainText extracts text from spans', () {
      final block = NoteBlockModel(
        id: 'b-1',
        noteId: 'n-1',
        blockType: BlockType.paragraph,
        content: {
          'spans': [
            {'text': 'Hello '},
            {'text': 'world'},
          ]
        },
        orderIndex: 0,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(block.plainText, 'Hello world');
    });

    test('plainText returns empty for content without text or spans', () {
      final block = NoteBlockModel(
        id: 'b-1',
        noteId: 'n-1',
        blockType: BlockType.divider,
        content: {},
        orderIndex: 0,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(block.plainText, '');
    });

    test('isChecked true for checked checkbox', () {
      final block = NoteBlockModel(
        id: 'b-1',
        noteId: 'n-1',
        blockType: BlockType.checkbox,
        content: {'text': 'Task', 'checked': true},
        orderIndex: 0,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(block.isChecked, true);
    });

    test('isChecked false for unchecked checkbox', () {
      final block = NoteBlockModel(
        id: 'b-1',
        noteId: 'n-1',
        blockType: BlockType.checkbox,
        content: {'text': 'Task', 'checked': false},
        orderIndex: 0,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(block.isChecked, false);
    });

    test('isChecked false for non-checkbox block', () {
      final block = NoteBlockModel(
        id: 'b-1',
        noteId: 'n-1',
        blockType: BlockType.paragraph,
        content: {'text': 'Not a checkbox', 'checked': true},
        orderIndex: 0,
        updatedAt: 1000,
        version: 1,
        deleted: 0,
        createdAt: 1000,
      );
      expect(block.isChecked, false);
    });

    group('toJson / fromJson round-trip', () {
      test('round-trip preserves all fields', () {
        final original = NoteBlockModel(
          id: 'b-rt',
          noteId: 'n-rt',
          blockType: BlockType.heading1,
          content: {'text': 'Title'},
          orderIndex: 0,
          updatedAt: 1700000000000,
          version: 2,
          deleted: 0,
          createdAt: 1699000000000,
        );

        final json = original.toJson();
        final restored = NoteBlockModel.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.noteId, original.noteId);
        expect(restored.blockType, original.blockType);
        expect(restored.content, original.content);
        expect(restored.orderIndex, original.orderIndex);
        expect(restored.updatedAt, original.updatedAt);
        expect(restored.version, original.version);
        expect(restored.deleted, original.deleted);
        expect(restored.createdAt, original.createdAt);
      });

      test('fromJson handles content as String', () {
        final json = {
          'id': 'b-1',
          'noteId': 'n-1',
          'blockType': 'paragraph',
          'content': '{"text":"Parsed"}',
          'orderIndex': 0,
          'updatedAt': 1000,
          'version': 1,
          'deleted': 0,
          'createdAt': 1000,
        };

        final block = NoteBlockModel.fromJson(json);
        expect(block.content, {'text': 'Parsed'});
      });

      test('fromJson defaults deleted to 0', () {
        final json = {
          'id': 'b-1',
          'noteId': 'n-1',
          'blockType': 'paragraph',
          'content': <String, dynamic>{},
          'orderIndex': 0,
          'updatedAt': 1000,
          'version': 1,
          'createdAt': 1000,
        };

        final block = NoteBlockModel.fromJson(json);
        expect(block.deleted, 0);
      });
    });

    group('create factory', () {
      test('creates block with version 1 and deleted 0', () {
        final block = NoteBlockModel.create(
          id: 'b-new',
          noteId: 'n-1',
          blockType: BlockType.bulletList,
          content: {'text': 'Item'},
          orderIndex: 2,
        );

        expect(block.version, 1);
        expect(block.deleted, 0);
        expect(block.blockType, BlockType.bulletList);
        expect(block.orderIndex, 2);
      });
    });

    group('paragraph factory', () {
      test('creates paragraph block with text', () {
        final block = NoteBlockModel.paragraph(
          id: 'b-p',
          noteId: 'n-1',
          orderIndex: 0,
          text: 'Hello',
        );

        expect(block.blockType, BlockType.paragraph);
        expect(block.plainText, 'Hello');
        expect(block.version, 1);
      });

      test('defaults to empty text', () {
        final block = NoteBlockModel.paragraph(
          id: 'b-p',
          noteId: 'n-1',
          orderIndex: 0,
        );

        expect(block.plainText, '');
      });
    });

    group('copyWithUpdate', () {
      test('updates content and increments version', () {
        final original = NoteBlockModel.paragraph(
          id: 'b-1',
          noteId: 'n-1',
          orderIndex: 0,
          text: 'Old',
        );

        final updated = original.copyWithUpdate(
          content: {'text': 'New'},
        );

        expect(updated.plainText, 'New');
        expect(updated.version, 2);
        expect(updated.id, original.id);
      });

      test('updates blockType', () {
        final original = NoteBlockModel.paragraph(
          id: 'b-1',
          noteId: 'n-1',
          orderIndex: 0,
        );

        final updated = original.copyWithUpdate(
          blockType: BlockType.heading1,
        );

        expect(updated.blockType, BlockType.heading1);
      });
    });

    group('softDelete', () {
      test('sets deleted to 1 and increments version', () {
        final block = NoteBlockModel.paragraph(
          id: 'b-1',
          noteId: 'n-1',
          orderIndex: 0,
        );

        final deleted = block.softDelete();
        expect(deleted.isDeleted, true);
        expect(deleted.version, 2);
      });
    });

    group('equality', () {
      test('equal when same id and version', () {
        final a = NoteBlockModel(
          id: 'b-1', noteId: 'n-1', blockType: BlockType.paragraph,
          content: {'text': 'A'}, orderIndex: 0,
          updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
        );
        final b = NoteBlockModel(
          id: 'b-1', noteId: 'n-2', blockType: BlockType.heading1,
          content: {'text': 'B'}, orderIndex: 5,
          updatedAt: 2000, version: 1, deleted: 0, createdAt: 500,
        );

        expect(a, equals(b));
      });

      test('not equal when different version', () {
        final a = NoteBlockModel(
          id: 'b-1', noteId: 'n-1', blockType: BlockType.paragraph,
          content: {}, orderIndex: 0,
          updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
        );
        final b = NoteBlockModel(
          id: 'b-1', noteId: 'n-1', blockType: BlockType.paragraph,
          content: {}, orderIndex: 0,
          updatedAt: 1000, version: 2, deleted: 0, createdAt: 1000,
        );

        expect(a, isNot(equals(b)));
      });
    });

    test('contentJson returns JSON string', () {
      final block = NoteBlockModel(
        id: 'b-1', noteId: 'n-1', blockType: BlockType.paragraph,
        content: {'text': 'hello'}, orderIndex: 0,
        updatedAt: 1000, version: 1, deleted: 0, createdAt: 1000,
      );

      expect(block.contentJson, '{"text":"hello"}');
    });
  });
}
