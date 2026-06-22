import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/config/remote/remote_config_defaults.dart';
import 'package:notify/core/config/remote/remote_config_keys.dart';
import 'package:notify/core/config/remote/remote_config_service.dart';
import 'package:notify/core/config/remote/remote_config_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('defaults coverage', () {
    test('every key the app reads has an in-code default', () {
      for (final key in RcKeys.all) {
        expect(RemoteConfigDefaults.values.containsKey(key), isTrue,
            reason: 'RcKeys.$key is missing from RemoteConfigDefaults.values');
      }
    });
  });

  group('snapshot accessors', () {
    test('defaults snapshot reflects in-code defaults', () {
      final snap = RemoteConfigSnapshot.defaults();
      expect(snap.getBool(RcKeys.maintenanceMode), isFalse);
      expect(snap.getBool(RcKeys.featureSongs), isTrue);
      expect(snap.getInt(RcKeys.syncDebounceMs), 500);
      expect(snap.getJsonList(RcKeys.suggestedPrayers).length, 6);
    });

    test('getInt clamps to a safe band', () {
      final snap = RemoteConfigSnapshot({'limits.x': 1000000}, 0);
      expect(snap.getInt('limits.x', min: 1, max: 100), 100);
      final snap2 = RemoteConfigSnapshot({'limits.x': 0}, 0);
      expect(snap2.getInt('limits.x', min: 1, max: 100), 1);
    });

    test('wrong-typed value falls back', () {
      final snap = RemoteConfigSnapshot({RcKeys.featureSongs: 'oops'}, 0);
      expect(snap.getBool(RcKeys.featureSongs, fallback: true), isTrue);
    });
  });

  group('service merge + fallback', () {
    Future<RemoteConfigService> serviceWith(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      return RemoteConfigService(prefs: sp, apiBaseUrl: 'http://localhost');
    }

    test('no cache => pure defaults', () async {
      final svc = await serviceWith({});
      final snap = svc.loadCached();
      expect(snap.getBool(RcKeys.featureSongs), isTrue);
      expect(snap.configVersion, 0);
    });

    test('partial override overlays defaults, untouched keys keep default',
        () async {
      final bundle = jsonEncode({
        'configVersion': 9,
        'config': {
          RcKeys.featureSongs: {'type': 'bool', 'value': 'false'},
          RcKeys.syncDebounceMs: {'type': 'int', 'value': '250'},
        },
      });
      final svc = await serviceWith({'remote_config_bundle_json': bundle});
      final snap = svc.loadCached();
      expect(snap.getBool(RcKeys.featureSongs), isFalse); // overridden
      expect(snap.getInt(RcKeys.syncDebounceMs), 250); // overridden
      expect(snap.getBool(RcKeys.featureSocial), isTrue); // default kept
      expect(snap.configVersion, 9);
    });

    test('malformed value is skipped per-key, rest of bundle survives',
        () async {
      final bundle = jsonEncode({
        'configVersion': 3,
        'config': {
          RcKeys.featureSongs: {'type': 'bool', 'value': 'not-a-bool'},
          RcKeys.featureSocial: {'type': 'bool', 'value': 'false'},
        },
      });
      final svc = await serviceWith({'remote_config_bundle_json': bundle});
      final snap = svc.loadCached();
      expect(snap.getBool(RcKeys.featureSongs), isTrue); // bad value -> default
      expect(snap.getBool(RcKeys.featureSocial), isFalse); // good value applied
    });

    test('type-mismatched override is rejected; default stays the floor',
        () async {
      // An int key sent as a string must NOT collapse to getInt's method
      // fallback (0) — the override is rejected and the registry default (3) wins.
      final bundle = jsonEncode({
        'configVersion': 2,
        'config': {
          RcKeys.syncMaxRetries: {'type': 'string', 'value': '0'},
        },
      });
      final svc = await serviceWith({'remote_config_bundle_json': bundle});
      final snap = svc.loadCached();
      expect(snap.getInt(RcKeys.syncMaxRetries), 3); // registry default, not 0
    });

    test('correctly-typed override is applied', () async {
      final bundle = jsonEncode({
        'configVersion': 2,
        'config': {
          RcKeys.syncMaxRetries: {'type': 'int', 'value': '0'},
        },
      });
      final svc = await serviceWith({'remote_config_bundle_json': bundle});
      final snap = svc.loadCached();
      expect(snap.getInt(RcKeys.syncMaxRetries), 0); // explicit 0 honored
    });

    test('garbage cache => defaults (never throws)', () async {
      final svc = await serviceWith({'remote_config_bundle_json': '{not json'});
      final snap = svc.loadCached();
      expect(snap.getBool(RcKeys.featureSongs), isTrue);
    });

    test('json override decodes to list/map', () async {
      final bundle = jsonEncode({
        'configVersion': 1,
        'config': {
          'test.list': {
            'type': 'json',
            'value': '["#000000","#111111"]',
          },
        },
      });
      final svc = await serviceWith({'remote_config_bundle_json': bundle});
      final snap = svc.loadCached();
      expect(snap.getStringList('test.list'), ['#000000', '#111111']);
    });
  });
}
