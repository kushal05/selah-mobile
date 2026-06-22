import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/sync_config.dart';
import '../models/oplog_entry.dart';
import '../utils/sync_logger.dart';
import 'api_interceptor.dart';
import 'auth_service.dart';
import 'sync_api_client.dart';

Map<String, dynamic> _decodeJson(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

String _encodePushBody(List<Map<String, dynamic>> ops) =>
    jsonEncode({'operations': ops});

/// Create a [SyncApiException] from an HTTP response, extracting
/// error details from the JSON body when available.
///
/// For 429 responses, also extracts [SyncApiException.retryAfter] from:
/// 1. The `Retry-After` response header (authoritative, set by server)
/// 2. The `details.retryAfter` field in the JSON body (fallback)
SyncApiException _exceptionFromResponse(dynamic response) {
  final statusCode = response.statusCode as int;

  // Parse Retry-After header first (standard HTTP)
  int? retryAfter;
  if (statusCode == 429) {
    final headerValue = response.headers['retry-after'] as String?;
    if (headerValue != null) {
      retryAfter = int.tryParse(headerValue);
    }
  }

  try {
    final body = jsonDecode(response.body as String) as Map<String, dynamic>;

    // Fall back to details.retryAfter in JSON body if header was absent
    if (retryAfter == null && statusCode == 429) {
      final details = body['details'] as Map<String, dynamic>?;
      retryAfter = (details?['retryAfter'] as num?)?.toInt();
    }

    return SyncApiException(
      code: body['error'] as String? ?? 'UNKNOWN_ERROR',
      message: body['message'] as String? ?? 'Unknown error',
      statusCode: statusCode,
      retryAfter: retryAfter,
    );
  } catch (_) {
    return SyncApiException(
      code: 'HTTP_ERROR',
      message: 'HTTP $statusCode: ${response.reasonPhrase}',
      statusCode: statusCode,
      retryAfter: retryAfter,
    );
  }
}

/// HTTP implementation of SyncApiClient with actual network calls.
///
/// Uses [ApiInterceptor] for automatic token refresh and retry logic.
/// Uses web_socket_channel for WebSocket real-time notifications.
class HttpSyncClient implements SyncApiClient {
  final SyncConfig config;
  final AuthService authService;
  final ApiInterceptor interceptor;
  final String deviceId;

  WebSocketChannel? _webSocket;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isConnecting = false;
  bool _sessionRevoked = false;
  bool _disposed = false;

  final _realTimeController = StreamController<void>.broadcast();

  HttpSyncClient({
    required this.config,
    required this.authService,
    required this.interceptor,
    required this.deviceId,
  });

  /// Headers for sync requests (includes device ID).
  Map<String, String> get _headers => interceptor.headers(deviceId: deviceId);

  @override
  Future<bool> isConnected() async {
    try {
      final response = await interceptor.get(
        Uri.parse(config.healthEndpoint),
        headers: _headers,
        timeout: const Duration(seconds: 10),
      );
      return response.statusCode == 200;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> pushOperation(OplogEntry operation) async {
    await interceptor.ensureValidToken(deviceId: deviceId);

    final response = await interceptor.post(
      Uri.parse(config.pushEndpoint),
      headers: _headers,
      body: jsonEncode(operation.toJson()),
      timeout: config.syncHttpTimeout,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['serverTimestamp'] as int;
    }

    throw _exceptionFromResponse(response);
  }

  @override
  Future<List<int>> pushOperations(List<OplogEntry> operations) async {
    if (operations.isEmpty) return [];

    // Batch if within limit, otherwise push in chunks
    if (operations.length <= config.maxBatchSize) {
      return _pushBatch(operations);
    }

    // Push in batches, collecting results and tracking failures
    final timestamps = <int>[];
    SyncApiException? lastError;

    for (var i = 0; i < operations.length; i += config.maxBatchSize) {
      final batch = operations.skip(i).take(config.maxBatchSize).toList();
      try {
        final batchTimestamps = await _pushBatch(batch);
        timestamps.addAll(batchTimestamps);
      } on SyncApiException catch (e) {
        lastError = e;
        // Stop processing further batches to preserve operation order
        break;
      }
    }

    if (lastError != null) {
      final allPartialTimestamps = [
        ...timestamps,
        ...lastError.partialTimestamps,
      ];
      throw SyncApiException(
        code: lastError.code,
        message: lastError.message,
        statusCode: lastError.statusCode,
        partialTimestamps: allPartialTimestamps,
        retryAfter: lastError.retryAfter,
      );
    }

    return timestamps;
  }

  Future<List<int>> _pushBatch(List<OplogEntry> operations) async {
    await interceptor.ensureValidToken(deviceId: deviceId);

    final opJsonList = operations.map((op) => op.toJson()).toList();
    final requestBody = await compute(_encodePushBody, opJsonList);

    SyncLogger.info(
      'Push batch: ${operations.length} operations to ${config.pushBatchEndpoint}',
    );

    final response = await interceptor.post(
      Uri.parse(config.pushBatchEndpoint),
      headers: _headers,
      body: requestBody,
      timeout: config.syncHttpTimeout,
    );

    SyncLogger.info('Push response: HTTP ${response.statusCode}');
    SyncLogger.debug('Push response body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = await compute(_decodeJson, response.body);
      final results = body['results'] as List? ?? [];
      final timestamps = <int>[];

      for (final raw in results) {
        final result = raw as Map<String, dynamic>;
        final success = result['success'] == true;
        if (!success) {
          throw SyncApiException(
            code: result['error'] as String? ?? 'PUSH_FAILED',
            message: 'Batch push failed for op ${result['opId']}',
            statusCode: response.statusCode,
            partialTimestamps: timestamps,
          );
        }
        timestamps.add(result['serverTimestamp'] as int);
      }

      SyncLogger.info(
        'Push successful: ${timestamps.length} operations confirmed',
      );
      return timestamps;
    }

    // Try to extract partial results from the error response
    List<int> partialTimestamps = const [];
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final partialResults = body['results'] as List?;
      if (partialResults != null && partialResults.isNotEmpty) {
        partialTimestamps = partialResults
            .map((r) => (r as Map<String, dynamic>)['serverTimestamp'] as int)
            .toList();
        SyncLogger.warning(
          'Partial batch success: ${partialTimestamps.length}/${operations.length} '
          'operations processed before failure (HTTP ${response.statusCode})',
        );
      }
    } catch (_) {
      // Could not parse partial results
    }

    final exception = _exceptionFromResponse(response);
    throw SyncApiException(
      code: exception.code,
      message: exception.message,
      statusCode: exception.statusCode,
      partialTimestamps: partialTimestamps,
      retryAfter: exception.retryAfter,
    );
  }

  @override
  Future<PullResponse> pullOperations({String? cursor}) async {
    await interceptor.ensureValidToken(deviceId: deviceId);

    final uri = Uri.parse(config.pullEndpoint).replace(
      queryParameters: {
        'deviceId': deviceId,
        'limit': config.pullBatchSize.toString(),
        if (cursor != null) 'cursor': cursor,
      },
    );

    final response = await interceptor.get(
      uri,
      headers: _headers,
      timeout: config.syncHttpTimeout,
    );

    if (response.statusCode == 200) {
      final body = await compute(_decodeJson, response.body);
      return PullResponse.fromJson(body);
    }

    throw _exceptionFromResponse(response);
  }

  // ==================== WebSocket ====================

  @override
  Stream<void> get realTimeUpdates => _realTimeController.stream;

  @override
  Future<void> connectRealTime() async {
    if (_disposed) return;
    if (_isConnecting || _webSocket != null) {
      SyncLogger.debug('WebSocket: skipping connect (already connecting or connected)');
      return;
    }

    _isConnecting = true;
    _sessionRevoked = false;

    try {
      await interceptor.ensureValidToken(deviceId: deviceId);

      final token = authService.currentToken?.accessToken;
      if (token == null) {
        throw const SyncApiException(
          code: 'AUTH_REQUIRED',
          message: 'No auth token available',
        );
      }

      final wsUri = Uri.parse(config.wsEndpoint).replace(
        queryParameters: {
          'token': token,
          'deviceId': deviceId,
        },
      );

      SyncLogger.info('WebSocket: connecting to ${config.wsEndpoint}');
      _webSocket = WebSocketChannel.connect(wsUri);

      // Wait for connection
      await _webSocket!.ready;

      // Reset reconnect attempts on successful connection
      _reconnectAttempts = 0;
      SyncLogger.info('WebSocket: connected successfully');

      // Listen to messages
      _wsSubscription = _webSocket!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );
    } catch (e) {
      SyncLogger.warning('WebSocket: connection failed: $e');
      _cleanupWebSocket();
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _handleMessage(dynamic message) async {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'sync_available':
          SyncLogger.debug('WebSocket: sync_available received');
          _realTimeController.add(null);
          break;

        case 'session_revoked':
          SyncLogger.warning('WebSocket: session revoked by server');
          _sessionRevoked = true;
          await authService.clearToken();
          _cleanupWebSocket();
          return;

        case 'error':
          final errorMessage = data['message'] as String?;
          SyncLogger.warning('WebSocket: server error: $errorMessage');
          break;
      }
    } catch (e) {
      SyncLogger.error('WebSocket: error handling message', e);
    }
  }

  void _handleError(Object error) {
    SyncLogger.error('WebSocket: stream error', error);
    _cleanupWebSocket();
    _scheduleReconnect();
  }

  void _handleDone() {
    SyncLogger.info('WebSocket: connection closed');
    _cleanupWebSocket();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _sessionRevoked) return;

    _reconnectTimer?.cancel();

    // Calculate delay with exponential backoff
    final delay = Duration(
      milliseconds: (config.wsReconnectDelay.inMilliseconds *
              (1 << _reconnectAttempts))
          .clamp(
        config.wsReconnectDelay.inMilliseconds,
        config.wsMaxReconnectDelay.inMilliseconds,
      ),
    );

    _reconnectAttempts++;

    SyncLogger.info(
      'WebSocket: reconnecting in ${delay.inSeconds}s '
      '(attempt $_reconnectAttempts)',
    );

    _reconnectTimer = Timer(delay, () {
      if (!_disposed) {
        connectRealTime();
      }
    });
  }

  void _cleanupWebSocket() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    try {
      _webSocket?.sink.close();
    } catch (_) {
      // Ignore close errors
    }
    _webSocket = null;
  }

  @override
  Future<void> disconnectRealTime() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _cleanupWebSocket();
  }

  /// Dispose all resources. Call on logout or app termination.
  void dispose() {
    _disposed = true;
    disconnectRealTime();
    _realTimeController.close();
  }
}
