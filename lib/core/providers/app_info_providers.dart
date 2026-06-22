import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/app_update_service.dart';

/// Resolves the app's package info (name, version, build number) once.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

final _appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});

/// Checks for an available app update.
///
/// Returns [AppUpdateResult] when a newer build exists, null otherwise.
/// Both forced and optional updates are surfaced here.
/// The provider is invalidated on app resume (throttled to once per hour)
/// so forced updates are detected promptly.
final appUpdateProvider = FutureProvider<AppUpdateResult?>((ref) {
  return ref.read(_appUpdateServiceProvider).checkForUpdate();
});

/// Exposed so the Settings screen and [UpdateDialog] can trigger downloads.
final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return ref.read(_appUpdateServiceProvider);
});
