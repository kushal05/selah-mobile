import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/domain/models/text_span_format.dart';

void main() {
  group('TextSpanFormat serialization', () {
    test('new attributes round-trip through JSON', () {
      const f = TextSpanFormat(
        start: 1,
        end: 5,
        isBold: true,
        isCode: true,
        link: 'https://x.io',
      );
      final restored = TextSpanFormat.fromJson(f.toJson());
      expect(restored, f);
      expect(restored.isCode, true);
      expect(restored.link, 'https://x.io');
    });

    test('legacy JSON without isCode/link defaults safely (backward compat)', () {
      final legacy = {
        'start': 0,
        'end': 3,
        'isBold': true,
        'isItalic': false,
        'isUnderline': false,
        'isStrikethrough': false,
      };
      final f = TextSpanFormat.fromJson(legacy);
      expect(f.isBold, true);
      expect(f.isCode, false);
      expect(f.link, isNull);
    });

    test('toJson omits unset new attributes to stay compact', () {
      const f = TextSpanFormat(start: 0, end: 2, isBold: true);
      final json = f.toJson();
      expect(json.containsKey('isCode'), false);
      expect(json.containsKey('link'), false);
    });

    test('copyWith preserves link unless explicitly cleared', () {
      const f = TextSpanFormat(start: 0, end: 2, link: 'a');
      // Omitting link keeps it.
      expect(f.copyWith(start: 1).link, 'a');
      // Explicit null clears it.
      expect(f.copyWith(link: null).link, isNull);
    });

    test('hasFormatting true for code and link', () {
      expect(const TextSpanFormat(start: 0, end: 1, isCode: true).hasFormatting,
          true);
      expect(const TextSpanFormat(start: 0, end: 1, link: 'x').hasFormatting,
          true);
      expect(const TextSpanFormat(start: 0, end: 1).hasFormatting, false);
    });
  });
}
