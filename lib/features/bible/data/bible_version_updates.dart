import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/bible_version_info.dart';

/// A version installed before updates were tracked has no stamp. Every hosted
/// file was last written before this date, so a file hosted with a later
/// modification time is newer than any such install.
final DateTime kBibleUpdateBaseline = DateTime.utc(2026, 11, 13);

/// What the host says about a version's file right now.
class RemoteStamp {
  /// The file's ETag, without quotes.
  final String? etag;
  final DateTime? lastModified;

  const RemoteStamp({this.etag, this.lastModified});
}

/// Whether the hosted file is newer than the copy that was installed.
///
/// [installedStamp] is the ETag saved when the version was installed. Without
/// one (an install from before updates were tracked) the hosted file counts as
/// newer only if it was modified after [kBibleUpdateBaseline].
bool bibleVersionNeedsUpdate({
  required String? installedStamp,
  required RemoteStamp remote,
}) {
  if (installedStamp != null) {
    return remote.etag != null && remote.etag != installedStamp;
  }
  final modified = remote.lastModified;
  return modified != null && modified.isAfter(kBibleUpdateBaseline);
}

/// The stamp of each installed version, kept on this device only.
class BibleVersionStamps {
  final SharedPreferences _prefs;

  BibleVersionStamps(this._prefs);

  static String _key(String code) => 'bible_version_stamp_$code';

  String? read(String code) => _prefs.getString(_key(code));

  Future<void> write(String code, String stamp) =>
      _prefs.setString(_key(code), stamp);

  Future<void> clear(String code) => _prefs.remove(_key(code));
}

/// Asks the host, with a HEAD request per installed version, which of them have
/// a newer file. A version it cannot reach is left out: no answer is not an
/// update.
class BibleVersionUpdateChecker {
  final http.Client _client;
  final BibleVersionStamps _stamps;

  BibleVersionUpdateChecker(this._stamps, {http.Client? client})
      : _client = client ?? http.Client();

  Future<Set<String>> check(Iterable<BibleVersionInfo> installed) async {
    final updates = await Future.wait(installed.map(_checkOne));
    return updates.whereType<String>().toSet();
  }

  Future<String?> _checkOne(BibleVersionInfo info) async {
    try {
      final response = await _client
          .head(Uri.parse(info.downloadUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final remote = RemoteStamp(
        etag: bibleStampFromHeaders(response.headers),
        lastModified: _parseDate(response.headers['last-modified']),
      );
      return bibleVersionNeedsUpdate(
        installedStamp: _stamps.read(info.code),
        remote: remote,
      )
          ? info.code
          : null;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseDate(String? value) {
    if (value == null) return null;
    try {
      return HttpDate.parse(value);
    } catch (_) {
      return null;
    }
  }
}

/// The ETag in [headers] without its quotes, or null when there is none.
String? bibleStampFromHeaders(Map<String, String> headers) {
  final etag = headers['etag'];
  if (etag == null || etag.isEmpty) return null;
  return etag.replaceAll('"', '');
}
