import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/presentation/widgets/editor/formatted_text_span.dart';

/// Link targets in a note can arrive from pasted markdown or from a note shared
/// by another user, so they are untrusted input. Only well-formed, known-safe
/// schemes may ever reach the OS launcher.
void main() {
  group('isSafeNoteLink', () {
    test('allows ordinary web and contact links', () {
      expect(isSafeNoteLink('http://example.com'), true);
      expect(isSafeNoteLink('https://example.com/a_b?q=1#f'), true);
      expect(isSafeNoteLink('mailto:a@b.com'), true);
      expect(isSafeNoteLink('tel:+15551234'), true);
      expect(isSafeNoteLink('HTTPS://EXAMPLE.COM'), true, reason: 'scheme is case-insensitive');
      expect(isSafeNoteLink('  https://example.com  '), true, reason: 'surrounding space tolerated');
    });

    test('blocks dangerous schemes', () {
      expect(isSafeNoteLink('javascript:alert(1)'), false);
      expect(isSafeNoteLink('JavaScript:alert(1)'), false);
      expect(isSafeNoteLink('file:///etc/passwd'), false);
      expect(isSafeNoteLink('intent://scan/#Intent;scheme=zxing;end'), false);
      expect(isSafeNoteLink('data:text/html,<script>x</script>'), false);
      expect(isSafeNoteLink('content://com.x/y'), false);
    });

    test('blocks relative or scheme-less targets', () {
      expect(isSafeNoteLink('example.com'), false);
      expect(isSafeNoteLink('/etc/passwd'), false);
      expect(isSafeNoteLink(''), false);
      expect(isSafeNoteLink('   '), false);
    });
  });
}
