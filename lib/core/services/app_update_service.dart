import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

// ─── Data models ─────────────────────────────────────────────────────────────

/// Parsed contents of the S3 metadata.json file.
class AppUpdateMetadata {
  final String latestVersion;
  final int latestBuildNumber;
  final int minSupportedBuild;
  final bool forceUpdate;
  final String apkUrl;
  final String releaseNotes;
  final int createdAt;

  const AppUpdateMetadata({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.minSupportedBuild,
    required this.forceUpdate,
    required this.apkUrl,
    required this.releaseNotes,
    required this.createdAt,
  });

  factory AppUpdateMetadata.fromJson(Map<String, dynamic> json) {
    return AppUpdateMetadata(
      latestVersion: json['latestVersion'] as String? ?? '',
      latestBuildNumber: (json['latestBuildNumber'] as num?)?.toInt() ?? 0,
      minSupportedBuild: (json['minSupportedBuild'] as num?)?.toInt() ?? 0,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      apkUrl: json['apkUrl'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Result surfaced to the UI when an update is available.
class AppUpdateResult {
  final String releaseNotes;

  /// Direct APK download URL. Empty on iOS.
  final String apkUrl;

  /// App Store / Play Store URL. Used when [apkUrl] is empty or on iOS.
  final String storeUrl;

  /// True = user cannot dismiss the dialog and must update.
  final bool isForced;

  final String latestVersion;
  final int latestBuildNumber;

  const AppUpdateResult({
    required this.releaseNotes,
    required this.apkUrl,
    required this.storeUrl,
    required this.isForced,
    required this.latestVersion,
    required this.latestBuildNumber,
  });

  /// Whether a direct APK install is available (Android + apkUrl present).
  bool get canInstallDirectly => Platform.isAndroid && apkUrl.isNotEmpty;
}

/// One entry in the rolling build manifest (manifest.json / manifest-qa.json).
/// Surfaced by [AppUpdateService.fetchAvailableBuilds] so the QA build picker
/// can let the user pick a specific build by version + buildNumber.
class AppBuildEntry {
  final String version;
  final int buildNumber;
  final String apkUrl;
  final String releaseNotes;
  final int createdAt;

  const AppBuildEntry({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.createdAt,
  });

  factory AppBuildEntry.fromJson(Map<String, dynamic> json) {
    return AppBuildEntry(
      version: json['version'] as String? ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      apkUrl: json['apkUrl'] as String? ?? '',
      releaseNotes: json['releaseNotes'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// Display label like `1.0.2 (102)` for list rows.
  String get displayLabel => '$version ($buildNumber)';
}

// ─── Download progress ────────────────────────────────────────────────────────

class DownloadProgress {
  /// 0.0–1.0. Indeterminate when [total] is 0.
  final double fraction;
  final int received;
  final int total;

  /// Non-null only on successful completion.
  final String? completedPath;

  /// Non-null only on failure.
  final String? error;

  const DownloadProgress({
    required this.fraction,
    required this.received,
    required this.total,
    this.completedPath,
    this.error,
  });

  bool get isDone => completedPath != null;
  bool get hasError => error != null;
  bool get isIndeterminate => total == 0 && !isDone && !hasError;
}

// ─── Service ──────────────────────────────────────────────────────────────────

/// Checks for OTA APK updates from S3 and handles download + install.
///
/// **Update check order:**
/// 1. If [AppConfig.updateMetadataUrl] is set → fetch metadata.json from S3.
/// 2. Otherwise → fall back to the backend `/v1/app/version` endpoint.
///
/// Both paths return null if no update is needed or the check fails silently.
class AppUpdateService {
  static const _installChannel = MethodChannel('com.example.notify/apk_install');

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns update info when a newer build is available; null otherwise.
  /// Always returns null in debug mode to avoid polluting development.
  Future<AppUpdateResult?> checkForUpdate() async {
    if (kDebugMode) return null;
    final metadataUrl = AppConfig.updateMetadataUrl;
    if (metadataUrl.isNotEmpty) {
      return _checkViaS3(metadataUrl);
    }
    return _checkViaBackend();
  }

  /// Returns the rolling list of recent builds from the S3 manifest, newest
  /// first. Filters out entries without an APK URL (only Android can install
  /// directly). Returns an empty list if the manifest is unavailable or the
  /// flavor has no manifest URL configured.
  Future<List<AppBuildEntry>> fetchAvailableBuilds() async {
    final manifestUrl = AppConfig.updateManifestUrl;
    if (manifestUrl.isEmpty) return const [];
    try {
      final response = await http
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return const [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final raw = (data['builds'] as List?) ?? const [];
      final builds = raw
          .whereType<Map<String, dynamic>>()
          .map(AppBuildEntry.fromJson)
          .where((b) => b.apkUrl.isNotEmpty)
          .toList();
      builds.sort((a, b) => b.buildNumber.compareTo(a.buildNumber));
      return builds;
    } catch (_) {
      return const [];
    }
  }

  /// Wraps an [AppBuildEntry] in the same shape [UpdateDialog] consumes for
  /// regular update flows. Always non-forced; the dialog only orchestrates
  /// download + install here.
  AppUpdateResult resultForBuild(AppBuildEntry build) {
    return AppUpdateResult(
      releaseNotes: build.releaseNotes,
      apkUrl: Platform.isAndroid ? build.apkUrl : '',
      storeUrl: '',
      isForced: false,
      latestVersion: build.version,
      latestBuildNumber: build.buildNumber,
    );
  }

  /// Streams APK download progress from [apkUrl] into the app's cache dir.
  /// Yields a terminal [DownloadProgress] with [completedPath] on success,
  /// or with [error] on failure.
  Stream<DownloadProgress> downloadApk(String apkUrl) async* {
    IOSink? sink;
    http.Client? client;
    try {
      client = http.Client();
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await client.send(request).timeout(const Duration(minutes: 5));

      final total = response.contentLength ?? 0;
      final cacheDir = await getTemporaryDirectory();
      final apkDir = Directory('${cacheDir.path}/apk_downloads');
      await apkDir.create(recursive: true);

      final fileName = Uri.parse(apkUrl).pathSegments.last;
      final filePath = '${apkDir.path}/$fileName';
      final file = File(filePath);
      sink = file.openWrite();

      int received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(
          fraction: total > 0 ? (received / total).clamp(0.0, 1.0) : 0,
          received: received,
          total: total,
        );
      }

      await sink.flush();
      await sink.close();
      sink = null;
      client.close();
      client = null;

      yield DownloadProgress(
        fraction: 1.0,
        received: received,
        total: received,
        completedPath: filePath,
      );
    } catch (e) {
      await sink?.close();
      client?.close();
      yield DownloadProgress(
        fraction: 0,
        received: 0,
        total: 0,
        error: e.toString(),
      );
    }
  }

  /// Triggers the Android system installer for the APK at [filePath].
  /// The file must be accessible via the app's FileProvider.
  Future<void> installApk(String filePath) async {
    if (!Platform.isAndroid) return;
    await _installChannel.invokeMethod<void>('installApk', {'filePath': filePath});
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<AppUpdateResult?> _checkViaS3(String metadataUrl) async {
    try {
      final response = await http
          .get(Uri.parse(metadataUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final metadata = AppUpdateMetadata.fromJson(data);

      final pkgInfo = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(pkgInfo.buildNumber) ?? 0;

      if (metadata.latestBuildNumber <= localBuild) return null;

      final isForced =
          metadata.forceUpdate || localBuild < metadata.minSupportedBuild;

      return AppUpdateResult(
        releaseNotes: metadata.releaseNotes,
        apkUrl: Platform.isAndroid ? metadata.apkUrl : '',
        storeUrl: '',
        isForced: isForced,
        latestVersion: metadata.latestVersion,
        latestBuildNumber: metadata.latestBuildNumber,
      );
    } catch (_) {
      return null;
    }
  }

  /// Legacy backend fallback: only returns a result when `forceUpdate = true`.
  Future<AppUpdateResult?> _checkViaBackend() async {
    try {
      final response = await http
          .get(Uri.parse('${AppConfig.apiBaseUrl}/v1/app/version'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final forceUpdate = data['forceUpdate'] as bool? ?? false;
      if (!forceUpdate) return null;

      final releaseNotes = data['releaseNotes'] as String? ?? '';
      final androidUrl = data['androidUrl'] as String? ?? '';
      final iosUrl = data['iosUrl'] as String? ?? '';

      return AppUpdateResult(
        releaseNotes: releaseNotes,
        apkUrl: Platform.isAndroid ? androidUrl : '',
        storeUrl: Platform.isIOS ? iosUrl : '',
        isForced: true,
        latestVersion: data['latestVersion'] as String? ?? '',
        latestBuildNumber: 0,
      );
    } catch (_) {
      return null;
    }
  }
}
