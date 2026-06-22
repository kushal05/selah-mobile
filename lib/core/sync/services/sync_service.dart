import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/services/note_block_fts_service.dart';
import '../../database/sync_database.dart';
import '../config/sync_config.dart';
import '../engine/sync_engine.dart';
import '../engine/sync_state_machine.dart';
import '../utils/sync_logger.dart';
import 'api_interceptor.dart';
import 'auth_service.dart';
import 'http_sync_client.dart';
import '../../testing/test_clock.dart';

/// Key for storing device ID in shared preferences
const _deviceIdKey = 'sync_device_id';

/// Main sync service that orchestrates all sync functionality
///
/// Responsibilities:
/// - Initialize sync engine with proper configuration
/// - Manage device ID generation and persistence
/// - Handle connectivity changes (pause/resume sync)
/// - Manage WebSocket real-time connection
/// - Provide sync status to the UI
/// - Health check on startup
class SyncService {
  final SyncDatabase _db;
  final SyncConfig _config;
  final AuthService _authService;
  final ApiInterceptor _interceptor;

  late final HttpSyncClient _apiClient;
  late final SyncEngine _syncEngine;
  late final String _deviceId;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<void>? _realTimeSubscription;
  StreamSubscription<AuthToken?>? _authSubscription;
  StreamSubscription? _oplogSubscription;

  bool _isInitialized = false;
  bool _isOnline = true;
  bool _isSyncPaused = false;

  /// Guards concurrent device ID generation
  Completer<String>? _deviceIdCompleter;

  /// Debounce timer to coalesce rapid sync triggers
  Timer? _syncDebounceTimer;
  static const _syncDebounceDelay = Duration(milliseconds: 500);

  final _progressController = StreamController<SyncProgress>.broadcast();

  /// Stream of sync progress updates
  Stream<SyncProgress> get progressStream => _progressController.stream;

  /// Whether the sync service is initialized
  bool get isInitialized => _isInitialized;

  /// Whether the device is online
  bool get isOnline => _isOnline;

  /// Whether sync is paused due to connectivity loss
  bool get isSyncPaused => _isSyncPaused;

  /// The sync engine (available after initialization)
  SyncEngine get engine {
    if (!_isInitialized) {
      throw StateError('SyncService not initialized. Call initialize() first.');
    }
    return _syncEngine;
  }

  /// Current device ID
  String get deviceId {
    if (!_isInitialized) {
      throw StateError('SyncService not initialized. Call initialize() first.');
    }
    return _deviceId;
  }

  final NoteBlockFtsService _ftsService;

  SyncService({
    required SyncDatabase db,
    required SyncConfig config,
    required AuthService authService,
    required ApiInterceptor interceptor,
    required NoteBlockFtsService ftsService,
  })  : _db = db,
        _config = config,
        _authService = authService,
        _interceptor = interceptor,
        _ftsService = ftsService;

  /// Initialize the sync service
  Future<void> initialize() async {
    if (_isInitialized) return;

    SyncLogger.info('Initializing sync service...');

    // Generate or retrieve device ID
    _deviceId = await _getOrCreateDeviceId();
    SyncLogger.debug('Device ID: $_deviceId');

    // Create API client (uses shared interceptor)
    _apiClient = HttpSyncClient(
      config: _config,
      authService: _authService,
      interceptor: _interceptor,
      deviceId: _deviceId,
    );

    // Create sync engine
    _syncEngine = SyncEngine(
      db: _db,
      apiClient: _apiClient,
      config: _config,
      ftsService: _ftsService,
      deviceId: _deviceId,
    );

    // Initialize engine
    await _syncEngine.initialize();

    // Forward engine progress to our stream. Stream errors are caught
    // and logged so they don't surface as uncaught async exceptions
    // (a runtime crash in release builds).
    _syncEngine.progressStream.listen(
      (progress) => _progressController.add(progress),
      onError: (Object error, StackTrace stack) {
        SyncLogger.error('Sync progress stream error', error, stack);
      },
    );

    // Listen for connectivity changes
    _setupConnectivityListener();

    // Listen for auth state changes
    _setupAuthListener();

    // Auto-sync when local writes create new oplog entries.
    // Listens only for INSERTs so that marking entries synced (UPDATE)
    // or garbage collection (DELETE) won't trigger unnecessary cycles.
    _oplogSubscription = _db
        .tableUpdates(TableUpdateQuery.onTable(
          _db.oplog,
          limitUpdateKind: UpdateKind.insert,
        ))
        .listen((_) {
      _debouncedSync();
    });

    _isInitialized = true;
    SyncLogger.info('Sync service initialized');

    // Health check on startup
    if (_authService.isAuthenticated) {
      _performHealthCheck();
    }

    // Initial sync if authenticated (token must be valid, not just non-null)
    if (_authService.isAuthenticated) {
      _syncEngine.sync();
    }
  }

  /// Perform a health check against the backend.
  Future<void> _performHealthCheck() async {
    try {
      final isHealthy = await _apiClient.isConnected();
      SyncLogger.info(
        'Health check: ${isHealthy ? "OK" : "FAILED"} '
        '(${_config.healthEndpoint})',
      );
      if (!isHealthy) {
        SyncLogger.warning(
          'Backend health check failed — sync may not work until server is reachable',
        );
      }
    } catch (e) {
      SyncLogger.warning('Health check error: $e');
    }
  }

  /// Generate or retrieve a unique device ID using shared preferences.
  ///
  /// Uses a Completer to guard against concurrent calls that could
  /// generate different IDs before the first one is persisted.
  Future<String> _getOrCreateDeviceId() async {
    // If another call is already generating, wait for it
    if (_deviceIdCompleter != null) {
      return _deviceIdCompleter!.future;
    }

    _deviceIdCompleter = Completer<String>();

    try {
      final prefs = await SharedPreferences.getInstance();

      // Try to get existing device ID
      final existingId = prefs.getString(_deviceIdKey);
      if (existingId != null && existingId.isNotEmpty) {
        SyncLogger.debug('Device ID loaded from storage: $existingId');
        _deviceIdCompleter!.complete(existingId);
        return existingId;
      }

      // Generate new device ID
      final deviceId = await _generateDeviceId();

      // Save to shared preferences
      await prefs.setString(_deviceIdKey, deviceId);
      SyncLogger.info('New device ID generated and persisted: $deviceId');

      _deviceIdCompleter!.complete(deviceId);
      return deviceId;
    } catch (e) {
      _deviceIdCompleter!.completeError(e);
      rethrow;
    } finally {
      _deviceIdCompleter = null;
    }
  }

  /// Generate a unique device ID based on platform
  Future<String> _generateDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return 'android_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return 'ios_${iosInfo.identifierForVendor ?? _generateUuid()}';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        return 'windows_${windowsInfo.deviceId}';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return 'macos_${macInfo.systemGUID ?? _generateUuid()}';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return 'linux_${linuxInfo.machineId ?? _generateUuid()}';
      }
    } catch (e) {
      SyncLogger.warning('Failed to get device info: $e');
    }

    // Fallback to UUID
    return 'device_${_generateUuid()}';
  }

  /// Generate a simple UUID
  String _generateUuid() {
    final now = TestClock.now();
    final random = now.hashCode ^ identityHashCode(this);
    return '${now.toRadixString(16)}-${random.toRadixString(16)}';
  }

  /// Debounced sync trigger that coalesces rapid events
  /// (connectivity flapping, multiple WebSocket notifications, etc.)
  /// into a single sync cycle.
  void _debouncedSync() {
    if (_isSyncPaused || !_isOnline) {
      SyncLogger.debug(
        'Sync trigger ignored: paused=$_isSyncPaused, online=$_isOnline',
      );
      return;
    }

    // Suppress automated triggers while the engine is in degraded state to
    // avoid log spam and battery drain. Manual sync, login, or
    // connectivity-restored events clear it.
    if (_syncEngine.state == SyncEngineState.degraded) {
      SyncLogger.debug('Sync trigger ignored: engine is degraded');
      return;
    }

    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(_syncDebounceDelay, () {
      _syncEngine.sync();
    });
  }

  /// Setup connectivity listener
  void _setupConnectivityListener() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);

      if (_isOnline && !wasOnline) {
        SyncLogger.info('Connectivity restored — resuming sync');
        _isSyncPaused = false;
        _syncEngine.onConnectivityRestored();
        _connectRealTime();
        // Run a health check before syncing
        _performHealthCheck().then((_) => _debouncedSync());
      } else if (!_isOnline && wasOnline) {
        SyncLogger.info('Connectivity lost — pausing sync');
        _isSyncPaused = true;
        _syncEngine.onConnectivityLost();
        _disconnectRealTime();
        // Emit offline progress (use 0 as placeholder; actual count is async)
        _syncEngine.getPendingOpsCount().then((count) {
          _progressController.add(SyncProgress.offline(count));
        });
      }
    });
  }

  /// Setup auth state listener
  void _setupAuthListener() {
    _authSubscription = _authService.authStateChanges.listen((token) {
      if (token != null) {
        SyncLogger.info('User authenticated, starting sync');
        _isSyncPaused = false;
        // A fresh authentication is a chance to recover from a degraded
        // engine state. syncNow() clears it before attempting.
        if (_syncEngine.state == SyncEngineState.degraded) {
          _syncEngine.syncNow();
        } else {
          _debouncedSync();
        }
        _connectRealTime();
      } else {
        SyncLogger.info('User logged out, stopping real-time');
        _isSyncPaused = true;
        _disconnectRealTime();
      }
    });
  }

  /// Connect to real-time WebSocket
  Future<void> _connectRealTime() async {
    if (!_isOnline || _authService.currentToken == null) return;

    try {
      await _apiClient.connectRealTime();

      // Listen for real-time updates (cancel previous subscription first)
      _realTimeSubscription?.cancel();
      _realTimeSubscription = _apiClient.realTimeUpdates.listen((_) {
        SyncLogger.debug('Real-time sync notification received');
        _debouncedSync();
      });

      SyncLogger.info('Real-time connection established');
    } catch (e) {
      SyncLogger.warning('Failed to connect real-time: $e');
    }
  }

  /// Disconnect from real-time WebSocket
  Future<void> _disconnectRealTime() async {
    _realTimeSubscription?.cancel();
    _realTimeSubscription = null;
    await _apiClient.disconnectRealTime();
  }

  /// Trigger manual sync
  Future<SyncResult> syncNow() async {
    if (!_isInitialized) {
      throw StateError('SyncService not initialized');
    }
    if (_isSyncPaused) {
      SyncLogger.warning('Manual sync requested while paused (offline)');
    }
    return _syncEngine.syncNow();
  }

  /// Reset the remote cursor and perform a full snapshot pull.
  Future<SyncResult> resetAndSync() async {
    await initialize();
    return _syncEngine.resetAndSync();
  }

  /// Called when app is resumed from background
  void onAppResumed() {
    if (_isInitialized) {
      SyncLogger.info('App resumed from background');
      _syncEngine.onAppResumed();
      // Reconnect WebSocket which may have been killed in background
      if (_isOnline && _authService.currentToken != null) {
        _connectRealTime();
      }
    }
  }

  /// Called when app is paused/backgrounded
  void onAppPaused() {
    SyncLogger.info('App going to background');
    // Gracefully close WebSocket to prevent leaked connections
    _disconnectRealTime();
  }

  /// Get pending operations count
  Future<int> getPendingOpsCount() async {
    if (!_isInitialized) return 0;
    return _syncEngine.getPendingOpsCount();
  }

  /// Dispose all resources
  void dispose() {
    _syncDebounceTimer?.cancel();
    _connectivitySubscription?.cancel();
    _realTimeSubscription?.cancel();
    _authSubscription?.cancel();
    _oplogSubscription?.cancel();
    _apiClient.dispose();
    _syncEngine.dispose();
    _progressController.close();
  }
}
