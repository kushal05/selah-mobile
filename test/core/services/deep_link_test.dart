// A deep link is untrusted input that turns into a route.
//
// bookId and chapter go through int.tryParse; the translation did not, and was
// interpolated straight into the path — so `?t=KJV%26verse=999` arrived as
// `…&translation=KJV&verse=999`, a parameter the link's author never wrote.

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/services/deep_link_service.dart';

String? path(String url) => DeepLinkService.uriToAppPath(Uri.parse(url));

Map<String, String> paramsOf(String route) =>
    Uri.parse(route).queryParameters;

void main() {
  group('what it refuses', () {
    test('another scheme', () {
      expect(path('http://selahapp.in/notes/abc'), isNull);
      expect(path('selah://notes/abc'), isNull);
    });

    test('another host', () {
      expect(path('https://example.com/notes/abc'), isNull);
      expect(path('https://selahapp.in.example.com/notes/abc'), isNull);
    });

    test('a bible link whose numbers are not numbers', () {
      expect(path('https://selahapp.in/bible/xx/3'), isNull);
      expect(path('https://selahapp.in/bible/1/yy'), isNull);
    });
  });

  group('bible links', () {
    test('map to the internal query form', () {
      final p = path('https://selahapp.in/bible/43/3?t=NKJV&v=16')!;
      expect(Uri.parse(p).path, '/bible/chapter');
      expect(paramsOf(p), {
        'bookId': '43',
        'chapter': '3',
        'translation': 'NKJV',
        'verse': '16',
      });
    });

    test('default the translation and omit an absent verse', () {
      final p = path('https://selahapp.in/bible/43/3')!;
      expect(paramsOf(p)['translation'], 'KJV');
      expect(paramsOf(p).containsKey('verse'), isFalse);
    });

    test('a verse of zero is dropped rather than passed on', () {
      expect(paramsOf(path('https://selahapp.in/bible/43/3?v=0')!)
          .containsKey('verse'), isFalse);
    });

    test('a crafted translation cannot add a parameter', () {
      final p = path(
          'https://selahapp.in/bible/1/3?t=KJV%26verse=999%26bookId=66')!;
      final params = paramsOf(p);

      expect(params['bookId'], '1', reason: 'bookId was overwritten');
      expect(params.containsKey('verse'), isFalse,
          reason: 'a verse parameter was injected');
      expect(params['translation'], 'KJV&verse=999&bookId=66',
          reason: 'the whole thing should stay one encoded value');
    });

    test('a translation with a hash or space survives intact', () {
      final p = path('https://selahapp.in/bible/1/3?t=New%20KJV%23x')!;
      expect(paramsOf(p)['translation'], 'New KJV#x');
    });
  });

  group('the pass-through branch', () {
    test('keeps a path and its query', () {
      expect(path('https://selahapp.in/notes/abc-123'), '/notes/abc-123');
      expect(path('https://selahapp.in/social/groups/g1?tab=members'),
          '/social/groups/g1?tab=members');
    });

    test('cannot be made to split one parameter into two', () {
      // The bible branch was fixed because it decoded a value and then
      // re-interpolated it. This branch forwards uri.query, which is still
      // encoded, so the same attack has to fail here for a different reason —
      // asserted rather than argued, because "the other branch is fine" is how
      // half a fix gets shipped.
      final p = path('https://selahapp.in/notes/abc?tab=one%26admin=true')!;
      final params = paramsOf(p);
      expect(params['tab'], 'one&admin=true');
      expect(params.containsKey('admin'), isFalse);
    });
  });
}
