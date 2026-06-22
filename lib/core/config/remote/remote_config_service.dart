import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_config_defaults.dart';
import 'remote_config_snapshot.dart';

/// Fetches the remote-config bundle from the backend, caches it locally for
/// offline + instant-startup use, and merges it over the in-code defaults.
///
/// The merge discipline is the whole safety story: defaults are the source of
/// truth, the server only overrides, and any failure (offline, non-200, bad
/// JSON, schema mismatch, bad value) collapses to the bundled defaults. Nothing
/// here ever throws.
class RemoteConfigService {
  static const _prefsKey = 'remote_config_bundle_json';
  static const _schemaVersion = 1;
  static const _fetchTimeout = Duration(seconds: 10);

  final SharedPreferences _prefs;
  final String _apiBaseUrl;
  final http.Client _client;

  RemoteConfigService({
    required SharedPreferences prefs,
    required String apiBaseUrl,
    http.Client? client,
  })  : _prefs = prefs,
        _apiBaseUrl = apiBaseUrl,
        _client = client ?? http.Client();

  /// Builds a snapshot synchronously from the cached bundle (or pure defaults
  /// on first launch / unreadable cache). Safe to call before the first frame.
  RemoteConfigSnapshot loadCached() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null) return RemoteConfigSnapshot.defaults();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return _merge(decoded);
    } catch (_) {
      return RemoteConfigSnapshot.defaults();
    }
  }

  /// Fetches the bundle for this client. Returns a fresh snapshot on success,
  /// or null on ANY failure (caller keeps the previous snapshot). Persists a
  /// successful bundle for the next cold start.
  Future<RemoteConfigSnapshot?> fetch({
    required String platform,
    required int build,
  }) async {
    try {
      final uri = Uri.parse('$_apiBaseUrl/v1/app/config')
          .replace(queryParameters: {'platform': platform, 'build': '$build'});
      final res = await _client.get(uri).timeout(_fetchTimeout);
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['schemaVersion'] != _schemaVersion) {
        debugPrint('RemoteConfig: schemaVersion mismatch — using defaults');
        return null;
      }

      // Cache the raw {configVersion, config} for the next cold start.
      final bundle = <String, dynamic>{
        'configVersion': body['configVersion'],
        'config': body['config'],
      };
      await _prefs.setString(_prefsKey, jsonEncode(bundle));
      return _merge(bundle);
    } catch (e) {
      debugPrint('RemoteConfig fetch failed (keeping cache): $e');
      return null;
    }
  }

  /// Overlays the server `config` map (key -> {type, value}) onto the in-code
  /// defaults. A value that fails to coerce is skipped for that key only, so a
  /// single bad entry can't corrupt the rest of the bundle.
  RemoteConfigSnapshot _merge(Map<String, dynamic> bundle) {
    final configVersion = (bundle['configVersion'] as num?)?.toInt() ?? 0;
    final merged = Map<String, Object?>.from(RemoteConfigDefaults.values);

    final config = bundle['config'];
    if (config is Map) {
      config.forEach((key, entry) {
        if (entry is! Map) return;
        final type = entry['type'];
        final value = entry['value'];
        if (type is! String || value is! String) return;
        final coerced = _coerce(type, value);
        if (coerced == null) return;
        // Reject a type-mismatched override (e.g. a string sent for an int key)
        // so the in-code default stays the floor. Without this, a wrong-typed
        // value would land in the map and the typed accessor would fall back to
        // its method default (0/'') instead of the registry default.
        final def = RemoteConfigDefaults.values['$key'];
        if (def != null && !_sameKind(def, coerced)) return;
        merged['$key'] = coerced;
      });
    }

    return RemoteConfigSnapshot(merged, configVersion);
  }

  /// Whether [b] is the same broad kind (bool/num/String/List/Map) as the
  /// in-code default [a]. Used to reject type-mismatched server overrides.
  bool _sameKind(Object a, Object b) {
    if (a is bool) return b is bool;
    if (a is num) return b is num; // covers int + double defaults
    if (a is String) return b is String;
    if (a is List) return b is List;
    if (a is Map) return b is Map;
    return a.runtimeType == b.runtimeType;
  }

  /// Coerces a server string value per its declared type. Returns null on any
  /// failure (the key then keeps its default).
  Object? _coerce(String type, String value) {
    try {
      switch (type) {
        case 'bool':
          if (value == 'true') return true;
          if (value == 'false') return false;
          return null;
        case 'int':
          return int.tryParse(value);
        case 'string':
          return value;
        case 'json':
          return jsonDecode(value);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
