import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/services/home_widget_service.dart';

void main() {
  String? map(String uri) =>
      HomeWidgetService.widgetUriToAppPath(Uri.parse(uri));

  group('widgetUriToAppPath', () {
    test('action widgets map to create/list routes', () {
      expect(map('selah://widget/notes/new'), '/notes/new');
      expect(map('selah://widget/prayers/new'), '/prayers/new');
      expect(map('selah://widget/songs'), '/songs');
      expect(map('selah://widget/pray-today'), '/prayers/today');
    });

    test('pinned widgets map to entity detail routes', () {
      expect(map('selah://widget/note?id=abc-123'), '/notes/abc-123');
      expect(map('selah://widget/prayer?id=xyz-789'), '/prayers/xyz-789');
    });

    test('pinned widgets without an id fall back to the list route', () {
      expect(map('selah://widget/note'), '/notes');
      expect(map('selah://widget/prayer'), '/prayers');
      expect(map('selah://widget/notes'), '/notes');
      expect(map('selah://widget/prayers'), '/prayers');
    });

    test('rejects foreign schemes and unknown targets', () {
      expect(map('https://selahapp.in/notes/abc'), isNull);
      expect(map('selah://widget/unknown'), isNull);
      expect(map('selah://widget'), isNull);
    });
  });
}
