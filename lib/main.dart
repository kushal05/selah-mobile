import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/config/app_config.dart';
import 'core/config/remote/remote_config_keys.dart';
import 'core/config/remote/remote_config_providers.dart';
import 'core/navigation/app_router.dart';
import 'core/navigation/routes.dart';
import 'core/providers/app_info_providers.dart';
import 'core/services/app_update_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/home_widget_service.dart';
import 'core/services/notification_service.dart';
import 'features/home/presentation/providers/widget_sync_coordinator.dart';
import 'core/sync/providers/sync_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/bible/data/bible_database_service.dart';
import 'features/bible/presentation/providers/bible_providers.dart';
import 'features/bible_search/presentation/providers/bible_search_providers.dart';
import 'shared/widgets/dialogs/update_dialog.dart';
import 'shared/widgets/maintenance_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (and register background FCM handler) before runApp.
  await FcmService.initialize();

  // Run independent initializations in parallel to reduce startup time.
  final notificationService = NotificationService();
  final bibleDbService = BibleDatabaseService();

  final results = await Future.wait([
    SharedPreferences.getInstance(),
    notificationService.initialize(),
  ]);
  final prefs = results[0] as SharedPreferences;

  // Bible DB init runs in the background — it's only needed for the Bible
  // tab and shouldn't block first-frame paint. The Bible tab providers
  // surface their own loading state if the user navigates there before
  // init completes.
  // ignore: discarded_futures
  bibleDbService.init().catchError((Object e, StackTrace st) {
    debugPrint('Bible DB initialization failed – Bible features will be '
        'unavailable: $e\n$st');
  });

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notificationService),
        // Override with the already-initialized instance so providers
        // don't create a second BibleDatabaseService.
        bibleDatabaseServiceProvider.overrideWith((_) => bibleDbService),
      ],
      child: const SelahApp(),
    ),
  );
}

/// Provider for the deep link service. Initialization is deferred to the
/// first frame callback in SelahApp to avoid racing with the router.
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final router = ref.watch(appRouterProvider);
  final service = DeepLinkService(router: router);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the home-screen widget service (routes widget taps). Like
/// [deepLinkServiceProvider], it is initialized from the first-frame callback
/// in SelahApp so the router is settled before any navigation.
final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) {
  final router = ref.watch(appRouterProvider);
  final service = HomeWidgetService(router: router);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Root application widget
class SelahApp extends ConsumerStatefulWidget {
  const SelahApp({super.key});

  @override
  ConsumerState<SelahApp> createState() => _SelahAppState();
}

class _SelahAppState extends ConsumerState<SelahApp>
    with WidgetsBindingObserver {
  bool _deepLinksInitialized = false;
  bool _updateDialogShown = false;

  /// An available update waiting to be shown. Held until the router settles on
  /// a route that won't be replaced out from under the dialog (see
  /// [_deferredUpdateLocations]).
  AppUpdateResult? _pendingUpdateResult;
  GoRouter? _router;

  /// Routes where the update prompt must not be shown. The splash and auth
  /// screens finish by calling `context.go(...)`, which rebuilds the root
  /// navigator's stack from the new location — silently discarding any
  /// imperatively pushed dialog. Showing the prompt here made it flash on
  /// screen and vanish within milliseconds.
  static const _deferredUpdateLocations = <String>{
    Routes.splash,
    Routes.onboarding,
    Routes.login,
    Routes.register,
    Routes.forgotPassword,
    Routes.completeProfile,
  };

  // Minimum interval between update checks on app resume (1 hour)
  static const _updateCheckInterval = Duration(hours: 1);

  // Minimum interval between remote-config refreshes on app resume. Matches the
  // server's 5-minute cache TTL so we never poll faster than the data changes.
  static const _remoteConfigRefreshInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Pre-warm the Bible search isolate (and its sqlite3 connection) after the
    // first frame is painted. The first user search would otherwise pay
    // ~150-300ms of isolate spawn + DB open + page-cache cold-read overhead;
    // doing it here moves that cost off the search-typed-and-pressed-enter
    // critical path. No-ops if the bible.db is not yet downloaded.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Retry a deferred update prompt once the router leaves splash/auth.
      final router = ref.read(appRouterProvider);
      _router = router;
      router.routerDelegate.addListener(_onRouteChanged);

      if (!ref.read(bibleDatabaseServiceProvider).isOpen) return;
      // ignore: discarded_futures
      ref.read(bibleSearchServiceProvider).getVerseCount();
    });
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The router moved to a new location — a pending update prompt may now be
  /// safe to show.
  void _onRouteChanged() {
    if (_pendingUpdateResult == null) return;
    // Defer: never push a dialog synchronously from a router notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tryShowPendingUpdate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final syncService = ref.read(syncServiceProvider).valueOrNull;

    switch (state) {
      case AppLifecycleState.resumed:
        syncService?.onAppResumed();
        _maybeReCheckUpdate();
        _maybeRefreshRemoteConfig();
        // Refresh widget data when the user returns to the app.
        try {
          ref.read(widgetSyncCoordinatorProvider).publishNow();
        } catch (_) {}
        break;
      case AppLifecycleState.paused:
        syncService?.onAppPaused();
        // Push the freshest widget payload before the OS samples the widgets.
        try {
          ref.read(widgetSyncCoordinatorProvider).publishNow();
        } catch (_) {}
        break;
      default:
        break;
    }
  }

  /// Invalidates the update provider on resume if at least [_updateCheckInterval]
  /// has passed since the last check. This ensures forced updates are detected
  /// promptly without hammering the backend on every resume.
  void _maybeReCheckUpdate() {
    final prefs = ref.read(sharedPreferencesProvider);
    final lastCheckMs = prefs.getInt('last_update_check_ms') ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - lastCheckMs >= _updateCheckInterval.inMilliseconds) {
      ref.invalidate(appUpdateProvider);
      _updateDialogShown = false;
    }
  }

  /// Refreshes remote config on resume, throttled so we don't refetch on every
  /// foreground. Best-effort: failures are swallowed by the service and the app
  /// keeps its last good (or default) config.
  void _maybeRefreshRemoteConfig() {
    final prefs = ref.read(sharedPreferencesProvider);
    final lastMs = prefs.getInt('last_remote_config_refresh_ms') ?? 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - lastMs >= _remoteConfigRefreshInterval.inMilliseconds) {
      prefs.setInt('last_remote_config_refresh_ms', nowMs);
      // ignore: discarded_futures
      ref.read(remoteConfigProvider.notifier).refresh();
    }
  }

  void _onUpdateResult(AppUpdateResult? result) {
    if (result == null) {
      // No update (any more). Drop anything still queued so a re-check that
      // clears the update can't leave a stale prompt to fire on route change.
      _pendingUpdateResult = null;
      return;
    }
    if (_updateDialogShown) return;
    _pendingUpdateResult = result;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tryShowPendingUpdate();
    });
  }

  /// Shows the pending update prompt, but only once the router has settled on a
  /// route that won't replace the navigator stack underneath it. If we're still
  /// on splash/auth the result stays pending and [_onRouteChanged] retries.
  void _tryShowPendingUpdate() {
    final result = _pendingUpdateResult;
    if (result == null || _updateDialogShown) return;

    final GoRouter router = _router ?? ref.read(appRouterProvider);
    final location = router.routerDelegate.currentConfiguration.uri.path;
    if (_deferredUpdateLocations.contains(location)) return;

    // Use rootNavigatorKey so the dialog is shown above all routes
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    _updateDialogShown = true;
    _pendingUpdateResult = null;

    // Record the check time only now that the prompt is actually on screen.
    // Recording it at check time meant a prompt the user never saw still armed
    // the resume throttle, suppressing it for the next hour.
    ref
        .read(sharedPreferencesProvider)
        .setInt('last_update_check_ms', DateTime.now().millisecondsSinceEpoch);

    UpdateDialog.show(ctx, result, ref.read(appUpdateServiceProvider));
  }

  @override
  Widget build(BuildContext context) {
    // Trigger one-time migration from AppDatabase → SyncDatabase
    final migration = ref.watch(notesMigrationProvider);
    if (migration is AsyncError) {
      debugPrint('Notes migration failed: ${migration.error}\n'
          '${migration.stackTrace}');
    }

    // Trigger one-time migration of inline promise tags/conditions → junction tables
    final promiseMigration = ref.watch(promiseInlineMigrationProvider);
    if (promiseMigration is AsyncError) {
      debugPrint('Promise inline migration failed: ${promiseMigration.error}\n'
          '${promiseMigration.stackTrace}');
    }

    // Purge trash items older than 30 days on each app startup
    final trashPurge = ref.watch(trashPurgeOnStartupProvider);
    if (trashPurge is AsyncError) {
      debugPrint('Trash purge failed: ${trashPurge.error}\n'
          '${trashPurge.stackTrace}');
    }

    // Listen for app update results and show dialog when an update is available.
    ref.listen<AsyncValue<AppUpdateResult?>>(
      appUpdateProvider,
      (prev, next) {
        // Reset flag when provider is refreshed (goes back to loading)
        if (next.isLoading) {
          _updateDialogShown = false;
          return;
        }
        next.whenData(_onUpdateResult);
      },
    );

    // Initialize deep link handling after the first frame, so the router
    // and auth state are fully settled before processing any incoming link.
    if (!_deepLinksInitialized) {
      _deepLinksInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(deepLinkServiceProvider).initialize();
        // Home-screen widgets: start routing taps and push an initial payload.
        // ignore: discarded_futures
        ref.read(homeWidgetServiceProvider).initialize();
        ref.read(widgetSyncCoordinatorProvider).publishNow();
      });
    }

    // Kick the one-shot remote-config refresh after first paint (fire-and-forget;
    // failures are swallowed by the service and never block the UI).
    ref.watch(remoteConfigRefreshProvider);

    // Backend kill switch: when the server enables maintenance mode, overlay a
    // blocking screen above the app. Defaults to false, so an empty/failed
    // config can never trigger it. `.select` rebuilds only on the flag changing.
    // The maintenance screen is overlaid via `builder` (rather than replacing
    // the whole app) so the router stays mounted — deep links and navigation
    // are not torn down and re-init, and the app is intact underneath when the
    // flag clears.
    final maintenance = ref.watch(
      remoteConfigProvider.select((s) => s.getBool(RcKeys.maintenanceMode)),
    );

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      theme: AppTheme.light(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (maintenance) const Positioned.fill(child: MaintenanceScreen()),
          ],
        );
      },
    );
  }
}
