import 'remote_config_defaults.dart';

/// An immutable, already-resolved view of the effective remote config: the
/// in-code defaults overlaid with any valid server overrides.
///
/// Every accessor is synchronous and NEVER throws — on a missing key or a
/// wrong-typed value it falls back to the in-code default (and then to an
/// explicit `fallback` argument), so call sites can read config like plain
/// data without guarding.
class RemoteConfigSnapshot {
  final Map<String, Object?> _values;

  /// The server's global config version this snapshot was built from (0 when
  /// running on pure defaults / before any successful fetch).
  final int configVersion;

  const RemoteConfigSnapshot(this._values, this.configVersion);

  /// A snapshot containing only the in-code defaults (offline / first launch).
  factory RemoteConfigSnapshot.defaults() => RemoteConfigSnapshot(
        Map<String, Object?>.from(RemoteConfigDefaults.values),
        0,
      );

  Object? _raw(String key) =>
      _values[key] ?? RemoteConfigDefaults.values[key];

  bool getBool(String key, {bool fallback = false}) {
    final v = _raw(key);
    return v is bool ? v : fallback;
  }

  /// Reads an int, optionally clamped to [min]..[max] so a fat-fingered server
  /// value can't thrash CPU or blow up a query.
  int getInt(String key, {int fallback = 0, int? min, int? max}) {
    final v = _raw(key);
    var result = v is int ? v : (v is num ? v.toInt() : fallback);
    if (min != null && result < min) result = min;
    if (max != null && result > max) result = max;
    return result;
  }

  String getString(String key, {String fallback = ''}) {
    final v = _raw(key);
    return v is String ? v : fallback;
  }

  List<String> getStringList(String key, {List<String> fallback = const []}) {
    final v = _raw(key);
    if (v is List) return v.map((e) => e.toString()).toList();
    return fallback;
  }

  /// Returns a JSON object (map). Falls back to an empty map.
  Map<String, dynamic> getJson(String key,
      {Map<String, dynamic> fallback = const {}}) {
    final v = _raw(key);
    if (v is Map) return Map<String, dynamic>.from(v);
    return fallback;
  }

  /// Returns a JSON array. Falls back to an empty list.
  List<dynamic> getJsonList(String key, {List<dynamic> fallback = const []}) {
    final v = _raw(key);
    if (v is List) return List<dynamic>.from(v);
    return fallback;
  }
}
