import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/domain/models/editor_block.dart';

void main() {
  group('EditorBlock.copyWith isChecked sentinel', () {
    const checkbox = EditorBlock(
      id: 'a',
      type: BlockType.checkbox,
      content: 'task',
      isChecked: true,
    );

    test('omitting isChecked preserves it', () {
      expect(checkbox.copyWith(content: 'x').isChecked, true);
    });

    test('explicit null clears it — a paragraph must not stay "checked"', () {
      final asParagraph =
          checkbox.copyWith(type: BlockType.paragraph, isChecked: null);
      expect(asParagraph.type, BlockType.paragraph);
      expect(asParagraph.isChecked, isNull);
    });

    test('explicit false sets it', () {
      expect(checkbox.copyWith(isChecked: false).isChecked, false);
    });
  });
}
