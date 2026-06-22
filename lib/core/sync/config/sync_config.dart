import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for sync services
///
/// Handles API URLs, timeouts, and environment-specific settings.
class SyncConfig {
  /// Base URL for the sync API
  final String apiBaseUrl;

  /// WebSocket URL for real-time updates
  final String wsBaseUrl;

  /// HTTP request timeout for regular API calls
  final Duration httpTimeout;

  /// HTTP request timeout for sync push/pull (larger payloads)
  final Duration syncHttpTimeout;

  /// WebSocket reconnect delay (initial)
  final Duration wsReconnectDelay;

  /// Maximum WebSocket reconnect delay
  final Duration wsMaxReconnectDelay;

  /// Maximum operations per batch push
  final int maxBatchSize;

  /// Pull batch size
  final int pullBatchSize;

  /// Periodic sync interval
  final Duration periodicSyncInterval;

  /// Maximum retries for transient errors (5xx, timeout)
  final int maxRetries;

  /// Initial retry delay for exponential backoff
  final Duration retryInitialDelay;

  /// Maximum retry delay
  final Duration retryMaxDelay;

  const SyncConfig({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    this.httpTimeout = const Duration(seconds: 12),
    this.syncHttpTimeout = const Duration(seconds: 30),
    this.wsReconnectDelay = const Duration(seconds: 1),
    this.wsMaxReconnectDelay = const Duration(minutes: 5),
    this.maxBatchSize = 100,
    this.pullBatchSize = 100,
    this.periodicSyncInterval = const Duration(minutes: 15),
    this.maxRetries = 3,
    this.retryInitialDelay = const Duration(seconds: 1),
    this.retryMaxDelay = const Duration(seconds: 30),
  });

  /// Production configuration
  factory SyncConfig.production() {
    return const SyncConfig(
      apiBaseUrl: 'https://api.selahapp.in',
      wsBaseUrl: 'wss://api.selahapp.in',
    );
  }

  /// QA configuration — points at the staging backend
  factory SyncConfig.qa() {
    return const SyncConfig(
      apiBaseUrl: 'https://api-qa.selahapp.in',
      wsBaseUrl: 'wss://api-qa.selahapp.in',
    );
  }

  /// Create from environment
  factory SyncConfig.fromEnvironment({
    required String apiBaseUrl,
    String? wsBaseUrl,
  }) {
    // Convert HTTP URL to WebSocket URL if not provided
    final wsUrl = wsBaseUrl ??
        apiBaseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');

    return SyncConfig(
      apiBaseUrl: apiBaseUrl,
      wsBaseUrl: wsUrl,
    );
  }

  /// Full push endpoint URL
  String get pushEndpoint => '$apiBaseUrl/v1/sync/push';

  /// Batch push endpoint URL
  String get pushBatchEndpoint => '$apiBaseUrl/v1/sync/push-batch';

  /// Pull endpoint URL
  String get pullEndpoint => '$apiBaseUrl/v1/sync/pull';

  /// WebSocket endpoint URL
  String get wsEndpoint => '$wsBaseUrl/v1/sync/ws';

  /// Health check endpoint URL
  String get healthEndpoint => '$apiBaseUrl/health';

  /// Token refresh endpoint URL
  String get refreshEndpoint => '$apiBaseUrl/v1/auth/refresh';
}

/// Service for managing sync configuration persistence
class SyncConfigService {
  static const _keyApiBaseUrl = 'sync_api_base_url';
  static const _keyWsBaseUrl = 'sync_ws_base_url';

  final SharedPreferences _prefs;

  SyncConfigService(this._prefs);

  /// Get saved configuration or default
  SyncConfig getConfig() {
    final apiBaseUrl = _prefs.getString(_keyApiBaseUrl);
    final wsBaseUrl = _prefs.getString(_keyWsBaseUrl);

    if (apiBaseUrl != null) {
      return SyncConfig.fromEnvironment(
        apiBaseUrl: apiBaseUrl,
        wsBaseUrl: wsBaseUrl,
      );
    }

    // Default to production config
    return SyncConfig.production();
  }

  /// Save configuration
  Future<void> saveConfig(SyncConfig config) async {
    await _prefs.setString(_keyApiBaseUrl, config.apiBaseUrl);
    await _prefs.setString(_keyWsBaseUrl, config.wsBaseUrl);
  }

  /// Clear saved configuration
  Future<void> clearConfig() async {
    await _prefs.remove(_keyApiBaseUrl);
    await _prefs.remove(_keyWsBaseUrl);
  }
}
