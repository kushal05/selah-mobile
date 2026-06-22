import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/sync_config.dart';
import 'api_interceptor.dart';
import 'auth_service.dart';

/// Base class for all online-required social API services.
///
/// Uses [ApiInterceptor] for automatic token refresh, retry with
/// exponential backoff, and request timeouts.
abstract class BaseSocialApiService {
  final SyncConfig config;
  final AuthService authService;
  final ApiInterceptor interceptor;

  BaseSocialApiService({
    required this.config,
    required this.authService,
    required this.interceptor,
  });

  /// Build full URI from a path under /v1/social/
  Uri buildUri(String path, [Map<String, String>? queryParams]) {
    return Uri.parse('${config.apiBaseUrl}/v1/social$path').replace(
      queryParameters:
          queryParams?.isNotEmpty == true ? queryParams : null,
    );
  }

  /// Auth + JSON headers.
  Map<String, String> get headers => interceptor.headers();

  /// GET with auto token refresh + retry via interceptor.
  Future<http.Response> httpGet(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    await interceptor.ensureValidToken();
    final uri = buildUri(path, queryParams);
    return interceptor.get(uri, headers: headers);
  }

  /// POST with auto token refresh + retry via interceptor.
  Future<http.Response> httpPost(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    await interceptor.ensureValidToken();
    final uri = buildUri(path);
    final encoded = body != null ? jsonEncode(body) : null;
    return interceptor.post(uri, headers: headers, body: encoded);
  }

  /// PUT with auto token refresh + retry via interceptor.
  Future<http.Response> httpPut(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    await interceptor.ensureValidToken();
    final uri = buildUri(path);
    final encoded = body != null ? jsonEncode(body) : null;
    return interceptor.put(uri, headers: headers, body: encoded);
  }

  /// DELETE with auto token refresh + retry via interceptor.
  Future<http.Response> httpDelete(String path) async {
    await interceptor.ensureValidToken();
    final uri = buildUri(path);
    return interceptor.delete(uri, headers: headers);
  }

  /// Parse response body as JSON map.
  Map<String, dynamic> parseBody(http.Response response) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Parse a JSON list from a key in the response body.
  List<Map<String, dynamic>> parseList(
    http.Response response,
    String key,
  ) {
    final body = parseBody(response);
    return (body[key] as List? ?? []).cast<Map<String, dynamic>>();
  }

  /// Throw if the response is not 2xx.
  void assertSuccess(http.Response response, String operation) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message;
    try {
      final body = parseBody(response);
      message = body['message'] as String? ??
          body['error'] as String? ??
          'HTTP ${response.statusCode}';
    } catch (_) {
      message = 'HTTP ${response.statusCode}';
    }
    throw SocialApiException(operation, response.statusCode, message);
  }
}

/// Exception thrown when a social API call fails.
class SocialApiException implements Exception {
  final String operation;
  final int statusCode;
  final String message;

  SocialApiException(this.operation, this.statusCode, this.message);

  @override
  String toString() => '$operation failed: $message';
}
