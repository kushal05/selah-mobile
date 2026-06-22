import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/sync_config.dart';
import '../utils/sync_logger.dart';
import 'auth_service.dart';

/// HTTP client wrapper that provides:
/// - Automatic token refresh on 401 responses
/// - Retry with exponential backoff for 5xx / timeout errors
/// - Configurable request timeouts
/// - Coalesced token refresh (concurrent 401s share one refresh)
/// - Diagnostics logging
class ApiInterceptor {
  final SyncConfig config;
  final AuthService authService;
  final http.Client _inner;

  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

  ApiInterceptor({
    required this.config,
    required this.authService,
    http.Client? httpClient,
  }) : _inner = httpClient ?? http.Client();

  /// Auth + JSON headers. Reads the latest token from [authService].
  Map<String, String> headers({String? deviceId}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    final authHeader = authService.getAuthorizationHeader();
    if (authHeader != null) h['Authorization'] = authHeader;
    if (deviceId != null) h['X-Device-Id'] = deviceId;
    return h;
  }

  /// Proactively refresh if the token is expired or about to expire.
  Future<void> ensureValidToken({String? deviceId}) async {
    final token = authService.currentToken;
    if (token == null) return;

    if (token.isExpired || token.isAboutToExpire) {
      await refreshAccessToken(deviceId: deviceId);
    }
  }

  /// Refresh the access token using the stored refresh token.
  ///
  /// Concurrent calls coalesce into a single refresh request.
  /// Returns `true` if the token was refreshed successfully.
  Future<bool> refreshAccessToken({String? deviceId}) async {
    if (_isRefreshing && _refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = authService.currentToken?.refreshToken;
      if (refreshToken == null) {
        SyncLogger.warning('[Interceptor] No refresh token available');
        _refreshCompleter!.complete(false);
        return false;
      }

      final body = <String, dynamic>{'refreshToken': refreshToken};
      if (deviceId != null) body['deviceId'] = deviceId;

      final response = await _inner
          .post(
            Uri.parse(config.refreshEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(config.httpTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tokens = data['tokens'] as Map<String, dynamic>;

        final currentUserId = authService.currentToken?.userId;
        if (currentUserId == null) {
          SyncLogger.warning(
            '[Interceptor] Token became null during refresh — possible logout race',
          );
          _refreshCompleter!.complete(false);
          return false;
        }

        final newToken = AuthToken(
          accessToken: tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String? ?? refreshToken,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            tokens['expiresAt'] as int,
          ),
          userId: currentUserId,
        );

        await authService.saveToken(newToken);
        SyncLogger.info('[Interceptor] Access token refreshed successfully');
        _refreshCompleter!.complete(true);
        return true;
      }

      // TOKEN_REUSE_DETECTED from the refresh endpoint means the server
      // detected a reused refresh token (potential theft) and revoked all
      // sessions. Log a security warning and clear local auth state.
      if (_isTokenReuseError(response)) {
        SyncLogger.warning(
          '[Interceptor] SECURITY: TOKEN_REUSE_DETECTED on refresh — '
          'possible token theft. All sessions revoked by server.',
        );
        await authService.clearToken();
        _refreshCompleter!.complete(false);
        return false;
      }

      SyncLogger.warning(
        '[Interceptor] Token refresh failed: HTTP ${response.statusCode}',
      );
      if (response.statusCode == 401 || response.statusCode == 403) {
        await authService.clearToken();
      }
      _refreshCompleter!.complete(false);
      return false;
    } on SocketException {
      SyncLogger.warning('[Interceptor] Token refresh failed: no network');
      _refreshCompleter!.complete(false);
      return false;
    } on TimeoutException {
      SyncLogger.warning('[Interceptor] Token refresh timed out');
      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      SyncLogger.error('[Interceptor] Token refresh error', e);
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  /// Execute a GET request with token refresh + retry logic.
  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) {
    return _executeWithRetry(
      () => _inner
          .get(url, headers: headers ?? this.headers())
          .timeout(timeout ?? config.httpTimeout),
      headers: headers,
      rebuildRequest: () => _inner
          .get(url, headers: headers ?? this.headers())
          .timeout(timeout ?? config.httpTimeout),
    );
  }

  /// Execute a POST request with token refresh + retry logic.
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    return _executeWithRetry(
      () => _inner
          .post(url, headers: headers ?? this.headers(), body: body)
          .timeout(timeout ?? config.httpTimeout),
      headers: headers,
      rebuildRequest: () => _inner
          .post(url, headers: headers ?? this.headers(), body: body)
          .timeout(timeout ?? config.httpTimeout),
    );
  }

  /// Execute a PUT request with token refresh + retry logic.
  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    return _executeWithRetry(
      () => _inner
          .put(url, headers: headers ?? this.headers(), body: body)
          .timeout(timeout ?? config.httpTimeout),
      headers: headers,
      rebuildRequest: () => _inner
          .put(url, headers: headers ?? this.headers(), body: body)
          .timeout(timeout ?? config.httpTimeout),
    );
  }

  /// Execute a DELETE request with token refresh + retry logic.
  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) {
    return _executeWithRetry(
      () => _inner
          .delete(url, headers: headers ?? this.headers())
          .timeout(timeout ?? config.httpTimeout),
      headers: headers,
      rebuildRequest: () => _inner
          .delete(url, headers: headers ?? this.headers())
          .timeout(timeout ?? config.httpTimeout),
    );
  }

  /// Core retry + token-refresh logic.
  ///
  /// 1. Execute [request].
  /// 2. On 401 → refresh token → retry once with [rebuildRequest]
  ///    (headers may have changed after refresh).
  /// 3. On 5xx or timeout → retry up to [config.maxRetries] with
  ///    exponential backoff.
  /// 4. On SocketException → rethrow immediately (offline).
  Future<http.Response> _executeWithRetry(
    Future<http.Response> Function() request, {
    Map<String, String>? headers,
    required Future<http.Response> Function() rebuildRequest,
  }) async {
    await ensureValidToken();

    int attempt = 0;
    while (true) {
      try {
        final response = attempt == 0 ? await request() : await rebuildRequest();

        // 401 — try refreshing the token once
        if (response.statusCode == 401 && attempt == 0) {
          // Check if this is a token reuse error — if so, the entire
          // refresh token family is compromised and the server has revoked
          // all sessions. Do NOT attempt a token refresh; go straight to logout.
          if (_isTokenReuseError(response)) {
            SyncLogger.warning(
              '[Interceptor] SECURITY: TOKEN_REUSE_DETECTED — '
              'skipping token refresh, clearing auth state',
            );
            await authService.clearToken();
            return response;
          }

          SyncLogger.debug('[Interceptor] 401 received, refreshing token');
          if (await refreshAccessToken()) {
            attempt++;
            continue;
          }
          return response;
        }

        // 5xx — transient server error, retry with backoff
        if (response.statusCode >= 500 && attempt < config.maxRetries) {
          final delay = _backoffDelay(attempt);
          SyncLogger.warning(
            '[Interceptor] ${response.statusCode} on attempt $attempt, '
            'retrying in ${delay.inMilliseconds}ms',
          );
          await Future.delayed(delay);
          attempt++;
          continue;
        }

        return response;
      } on TimeoutException {
        if (attempt < config.maxRetries) {
          final delay = _backoffDelay(attempt);
          SyncLogger.warning(
            '[Interceptor] Timeout on attempt $attempt, '
            'retrying in ${delay.inMilliseconds}ms',
          );
          await Future.delayed(delay);
          attempt++;
          continue;
        }
        rethrow;
      } on SocketException {
        // No network — don't retry
        rethrow;
      }
    }
  }

  /// Check whether an HTTP response contains a TOKEN_REUSE_DETECTED error code.
  ///
  /// The Go server returns `{"error": "TOKEN_REUSE_DETECTED", ...}` with a 401
  /// status when a refresh token is reused, indicating potential token theft.
  bool _isTokenReuseError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] == 'TOKEN_REUSE_DETECTED';
    } catch (_) {
      return false;
    }
  }

  /// Calculate exponential backoff delay with jitter.
  Duration _backoffDelay(int attempt) {
    final baseMs = config.retryInitialDelay.inMilliseconds;
    final maxMs = config.retryMaxDelay.inMilliseconds;
    final expMs = (baseMs * pow(2, attempt)).toInt().clamp(baseMs, maxMs);
    // Add ±25 % jitter to prevent thundering herd
    final jitter = (expMs * 0.25 * (Random().nextDouble() * 2 - 1)).toInt();
    return Duration(milliseconds: expMs + jitter);
  }

  /// Dispose the underlying HTTP client.
  void dispose() {
    _inner.close();
  }
}
