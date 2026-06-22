import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_info_providers.dart';
import '../../sync/providers/sync_providers.dart';
import '../app_config.dart';
import 'remote_config_service.dart';
import 'remote_config_snapshot.dart';

/// The remote-config service singleton. Depends on prefs (already overridden in
/// main). Uses the flavor's [AppConfig.apiBaseUrl] directly — NOT
/// `syncConfigProvider` — because syncConfig now reads remote-config limits, and
/// routing the service through it would create a provider cycle.
final remoteConfigServiceProvider = Provider<RemoteConfigService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = RemoteConfigService(
    prefs: prefs,
    apiBaseUrl: AppConfig.apiBaseUrl,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Holds the current merged config snapshot and refreshes it from the backend.
/// Seeded synchronously from the cached bundle (or defaults) so the first frame
/// is already correct and offline-safe.
class RemoteConfigNotifier extends StateNotifier<RemoteConfigSnapshot> {
  final RemoteConfigService _service;
  final Ref _ref;
  bool _appliedServerConfig = false;

  RemoteConfigNotifier(this._service, this._ref)
      : super(_service.loadCached());

  /// Best-effort fetch. The first successful server response is always applied;
  /// after that, state updates only when the config version changes, so an
  /// unchanged bundle never causes needless rebuilds. Applying the first fetch
  /// unconditionally guards against the seed/cache and server sharing a version.
  Future<void> refresh() async {
    final platform =
        defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

    var build = 0;
    try {
      final info = await _ref.read(packageInfoProvider.future);
      build = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      // package info unavailable — fall back to build 0 (build-gated rows skip)
    }

    final snap = await _service.fetch(platform: platform, build: build);
    if (snap == null) return;
    if (!_appliedServerConfig || snap.configVersion != state.configVersion) {
      _appliedServerConfig = true;
      state = snap;
    }
  }
}

/// Reactive snapshot the UI watches. Rebuilds when [RemoteConfigNotifier.refresh]
/// applies a newer bundle.
final remoteConfigProvider =
    StateNotifierProvider<RemoteConfigNotifier, RemoteConfigSnapshot>((ref) {
  return RemoteConfigNotifier(ref.watch(remoteConfigServiceProvider), ref);
});

/// One-shot startup refresh. Watched (fire-and-forget) from the root widget;
/// the UI never blocks on it.
final remoteConfigRefreshProvider = FutureProvider<void>((ref) async {
  await ref.read(remoteConfigProvider.notifier).refresh();
});

/// Ergonomic per-flag accessor: `ref.watch(featureFlagProvider(RcKeys.featureSongs))`.
final featureFlagProvider = Provider.family<bool, String>((ref, key) {
  return ref.watch(remoteConfigProvider).getBool(key, fallback: true);
});
