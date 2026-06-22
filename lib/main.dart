import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/config/app_config.dart';
import 'core/config/remote/remote_config_keys.dart';
import 'core/config/remote/remote_config_providers.dart';
import 'core/navigation/app_router.dart';
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
      if (!ref.read(bibleDatabaseServiceProvider).isOpen) return;
      // ignore: discarded_futures
      ref.read(bibleSearchServiceProvider).getVerseCount();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
    if (result == null || _updateDialogShown) return;
    _updateDialogShown = true;

    // Record the check time so resume throttling works
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setInt('last_update_check_ms', DateTime.now().millisecondsSinceEpoch);

    // Use rootNavigatorKey so the dialog is shown above all routes
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rootNavigatorKey.currentContext?.mounted == true) {
        UpdateDialog.show(
          rootNavigatorKey.currentContext!,
          result,
          ref.read(appUpdateServiceProvider),
        );
      }
    });
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
