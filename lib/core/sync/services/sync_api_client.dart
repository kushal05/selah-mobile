import 'dart:async';
import '../models/oplog_entry.dart';
import '../utils/sync_logger.dart';
import '../../testing/test_clock.dart';

/// Sync API exception
class SyncApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  /// Server timestamps for operations that succeeded before the failure.
  /// Non-empty when a batch push partially succeeded.
  final List<int> partialTimestamps;

  /// Seconds to wait before retrying, populated from the server's
  /// `Retry-After` header or `details.retryAfter` on 429 responses.
  final int? retryAfter;

  const SyncApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.partialTimestamps = const [],
    this.retryAfter,
  });

  /// Whether some operations succeeded before the failure
  bool get hasPartialResults => partialTimestamps.isNotEmpty;

  @override
  String toString() => 'SyncApiException($code): $message';
}

/// Response from pull operations endpoint
class PullResponse {
  /// Server-provided cursor for resuming pulls
  final String cursor;

  /// Operations to apply
  final List<OplogEntry> operations;

  /// Batch size used by server
  final int batchSize;

  /// Whether there are more operations to pull after this batch.
  /// Per backend spec, the server provides this field explicitly.
  /// Falls back to a heuristic (ops.length >= batchSize) if not provided.
  final bool hasMore;

  /// Whether the server requires the client to perform a full re-sync.
  /// When true, the client must reset its cursor and do a snapshot pull
  /// instead of continuing incremental sync. The operations in this
  /// response should NOT be processed.
  final bool requiresFullSync;

  /// Machine-readable reason for requiring full sync (e.g., "cursor_expired").
  final String? reason;

  /// Human-readable message explaining why full sync is required.
  final String? message;

  const PullResponse({
    required this.cursor,
    required this.operations,
    required this.batchSize,
    required this.hasMore,
    this.requiresFullSync = false,
    this.reason,
    this.message,
  });

  factory PullResponse.fromJson(Map<String, dynamic> json) {
    final rawOps = json['operations'] as List? ?? [];
    final ops = <OplogEntry>[];
    for (final e in rawOps) {
      try {
        ops.add(OplogEntry.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        // Skip unparseable operations instead of failing the entire batch.
        // This prevents one bad op (e.g., unknown entity type) from blocking
        // the pull of all other valid operations.
        SyncLogger.error(
          'Skipping unparseable pull operation: '
          'entityType=${e is Map ? e['entityType'] : '?'}, '
          'opId=${e is Map ? e['opId'] : '?'}',
          err,
        );
      }
    }

    final batchSize = json['batchSize'] as int? ?? 100;

    return PullResponse(
      cursor: json['cursor'] as String,
      operations: ops,
      batchSize: batchSize,
      // Use server-provided hasMore if available, otherwise fall back
      // to heuristic based on batch size
      hasMore: json['hasMore'] as bool? ?? rawOps.length >= batchSize,
      requiresFullSync: json['requiresFullSync'] as bool? ?? false,
      reason: json['reason'] as String?,
      message: json['message'] as String?,
    );
  }
}

/// Client for sync API communication
///
/// Per spec section 7:
/// Server Sync Endpoints:
/// - Push operations endpoint
/// - Pull operations endpoint
/// - WebSocket / real-time trigger logic
/// - Validation rules
///
/// This is an abstract interface that can be implemented
/// with HTTP, gRPC, or any other transport.
abstract class SyncApiClient {
  /// Check if the device is connected to the server
  Future<bool> isConnected();

  /// Push a single operation to the server
  ///
  /// Per spec section 5.2:
  /// - Push order must be preserved
  /// - Server uses op_id for idempotency
  ///
  /// Returns server timestamp for the operation
  Future<int> pushOperation(OplogEntry operation);

  /// Push multiple operations in a batch
  ///
  /// Returns server timestamps for each operation
  Future<List<int>> pushOperations(List<OplogEntry> operations);

  /// Pull operations from the server
  ///
  /// Per spec section 5.3:
  /// Server returns cursor and operations.
  /// Client applies ops in order and updates cursor.
  Future<PullResponse> pullOperations({String? cursor});

  /// Subscribe to real-time updates
  ///
  /// Per spec section 8:
  /// WebSocket + MongoDB Change Streams
  /// Client never trusts payload directly – it always
  /// re-applies via sync engine.
  Stream<void> get realTimeUpdates;

  /// Connect to real-time updates
  Future<void> connectRealTime();

  /// Disconnect from real-time updates
  Future<void> disconnectRealTime();
}

/// HTTP implementation of SyncApiClient
///
/// This implementation uses HTTP for push/pull
/// and WebSocket for real-time notifications.
class HttpSyncApiClient implements SyncApiClient {
  final String baseUrl;
  final String? authToken;
  final Duration timeout;

  // In a real implementation, these would be actual HTTP/WebSocket clients
  // For now, this serves as a contract definition

  HttpSyncApiClient({
    required this.baseUrl,
    this.authToken,
    this.timeout = const Duration(seconds: 30),
  });

  @override
  Future<bool> isConnected() async {
    // Implementation would check network connectivity
    // and optionally ping the server
    try {
      // Placeholder - real implementation would do HTTP HEAD or similar
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> pushOperation(OplogEntry operation) async {
    // POST /v1/sync/push
    // Body: operation.toJson()
    // Response: { serverTimestamp: 1234567890 }
    //
    // Server must:
    // 1. Validate op_id is unique (idempotency)
    // 2. Validate entity exists or is being created
    // 3. Apply operation to MongoDB
    // 4. Return server timestamp

    // Placeholder implementation
    // In production, this would be:
    // final response = await http.post(
    //   Uri.parse('$baseUrl/v1/sync/push'),
    //   headers: {
    //     'Content-Type': 'application/json',
    //     if (authToken != null) 'Authorization': 'Bearer $authToken',
    //   },
    //   body: requestBody,
    // );

    // Simulate server response
    await Future.delayed(const Duration(milliseconds: 100));
    return TestClock.now();
  }

  @override
  Future<List<int>> pushOperations(List<OplogEntry> operations) async {
    // POST /v1/sync/push-batch
    // Body: { operations: [...] }
    // Response: { serverTimestamps: [1234567890, ...] }

    final timestamps = <int>[];
    for (final op in operations) {
      final ts = await pushOperation(op);
      timestamps.add(ts);
    }
    return timestamps;
  }

  @override
  Future<PullResponse> pullOperations({String? cursor}) async {
    // GET /v1/sync/pull?cursor=abc123
    // Response:
    // {
    //   "cursor": "def456",
    //   "operations": [...],
    //   "batchSize": 100
    // }
    //
    // Server must:
    // 1. Return operations after cursor
    // 2. Limit to batch size
    // 3. Return new cursor for pagination

    // Placeholder implementation
    // In production, this would be:
    // final uri = Uri.parse('$baseUrl/v1/sync/pull')
    //     .replace(queryParameters: {if (cursor != null) 'cursor': cursor});
    // final response = await http.get(
    //   uri,
    //   headers: {
    //     if (authToken != null) 'Authorization': 'Bearer $authToken',
    //   },
    // );
    // return PullResponse.fromJson(jsonDecode(response.body));

    // Simulate empty response (no new operations)
    await Future.delayed(const Duration(milliseconds: 100));
    return PullResponse(
      cursor: cursor ?? 'initial',
      operations: [],
      batchSize: 100,
      hasMore: false,
    );
  }

  final _realTimeController = StreamController<void>.broadcast();

  @override
  Stream<void> get realTimeUpdates => _realTimeController.stream;

  @override
  Future<void> connectRealTime() async {
    // Connect to WebSocket
    // ws://$baseUrl/v1/sync/ws
    //
    // Per spec section 8:
    // MongoDB change -> Backend emits event -> WebSocket push to clients
    // Client triggers pull (never trusts payload directly)

    // Placeholder - real implementation would establish WebSocket
  }

  @override
  Future<void> disconnectRealTime() async {
    // Disconnect WebSocket
  }

  void dispose() {
    _realTimeController.close();
  }
}

/// Mock implementation for testing
///
/// Simulates server behavior including:
/// - Opaque cursor-based pagination (matching HttpSyncClient)
/// - Per-operation push with server timestamp assignment
/// - Configurable connectivity and error simulation
class MockSyncApiClient implements SyncApiClient {
  final List<OplogEntry> _serverOps = [];
  final _realTimeController = StreamController<void>.broadcast();
  bool _connected = true;
  int _batchSize;

  /// Optional callback to simulate push failures
  bool Function(OplogEntry)? shouldFailPush;

  MockSyncApiClient({int batchSize = 100}) : _batchSize = batchSize;

  void setConnected(bool connected) {
    _connected = connected;
  }

  /// Set the pull batch size (mirrors SyncConfig.pullBatchSize)
  set batchSize(int size) => _batchSize = size;

  void addServerOperation(OplogEntry op) {
    _serverOps.add(op);
    _realTimeController.add(null);
  }

  /// Add multiple server operations at once
  void addServerOperations(List<OplogEntry> ops) {
    _serverOps.addAll(ops);
    _realTimeController.add(null);
  }

  /// Clear all server operations
  void clearServerOperations() {
    _serverOps.clear();
  }

  @override
  Future<bool> isConnected() async => _connected;

  @override
  Future<int> pushOperation(OplogEntry operation) async {
    if (!_connected) {
      throw const SyncApiException(
        code: 'OFFLINE',
        message: 'Not connected',
      );
    }
    if (shouldFailPush != null && shouldFailPush!(operation)) {
      throw const SyncApiException(
        code: 'PUSH_FAILED',
        message: 'Simulated push failure',
        statusCode: 500,
      );
    }
    await Future.delayed(const Duration(milliseconds: 10));
    return TestClock.now();
  }

  @override
  Future<List<int>> pushOperations(List<OplogEntry> operations) async {
    if (!_connected) {
      throw const SyncApiException(
        code: 'OFFLINE',
        message: 'Not connected',
      );
    }
    final timestamps = <int>[];
    for (final op in operations) {
      try {
        timestamps.add(await pushOperation(op));
      } on SyncApiException catch (e) {
        // Propagate timestamps for ops that succeeded before the failure
        throw SyncApiException(
          code: e.code,
          message: e.message,
          statusCode: e.statusCode,
          partialTimestamps: timestamps,
        );
      }
    }
    return timestamps;
  }

  @override
  Future<PullResponse> pullOperations({String? cursor}) async {
    if (!_connected) {
      throw const SyncApiException(
        code: 'OFFLINE',
        message: 'Not connected',
      );
    }
    await Future.delayed(const Duration(milliseconds: 10));

    // Use opaque cursor format matching production behavior
    final startIndex = cursor != null ? int.tryParse(cursor) ?? 0 : 0;
    final endIndex = (startIndex + _batchSize).clamp(0, _serverOps.length);
    final ops = startIndex < _serverOps.length
        ? _serverOps.sublist(startIndex, endIndex)
        : <OplogEntry>[];

    return PullResponse(
      cursor: endIndex.toString(),
      operations: ops,
      batchSize: _batchSize,
      hasMore: endIndex < _serverOps.length,
    );
  }

  @override
  Stream<void> get realTimeUpdates => _realTimeController.stream;

  @override
  Future<void> connectRealTime() async {
    if (!_connected) {
      throw const SyncApiException(
        code: 'OFFLINE',
        message: 'Not connected',
      );
    }
  }

  @override
  Future<void> disconnectRealTime() async {}

  void dispose() {
    _realTimeController.close();
  }
}
