// The debug "Skip sign-in (test mode)" button mints a token the server never
// issued, so the first background sync gets a 401. The interceptor treats a
// failed refresh as a revoked session and clears local auth — which ejected
// the tester from home straight back to login, in a loop.
//
// These tests pin the two halves of the fix: a test session is recognised,
// and a 401 no longer destroys it.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/config/sync_config.dart';
import 'package:notify/core/sync/services/api_interceptor.dart';
import 'package:notify/core/sync/services/auth_service.dart';

/// Answers every request with [status], and counts what it was asked to do —
/// a test session should never reach the network at all.
class _StubClient extends http.BaseClient {
  final int status;
  int requestCount = 0;
  _StubClient(this.status);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    return http.StreamedResponse(
      Stream.value(<int>[]),
      status,
      request: request,
    );
  }
}

AuthToken _token({required String access, required String? refresh}) =>
    AuthToken(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.now().add(const Duration(days: 365)),
      userId: 'user-1',
    );

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ApiInterceptor interceptorFor(AuthService auth, http.Client client) =>
      ApiInterceptor(
        config: SyncConfig.fromEnvironment(apiBaseUrl: 'https://example.test'),
        authService: auth,
        httpClient: client,
      );

  group('isTestSession', () {
    test('is true for the token the skip button mints', () async {
      final auth = AuthService(prefs);
      await auth.saveToken(_token(
        access: AuthService.kTestAccessToken,
        refresh: AuthService.kTestRefreshToken,
      ));
      expect(auth.isTestSession, isTrue);
    });

    test('is false for a real token and when signed out', () async {
      final auth = AuthService(prefs);
      expect(auth.isTestSession, isFalse, reason: 'no token stored');

      await auth.saveToken(_token(access: 'real-access', refresh: 'real-r'));
      expect(auth.isTestSession, isFalse);
    });
  });

  group('refreshAccessToken', () {
    test('keeps the test session on 401 and makes no network call', () async {
      final auth = AuthService(prefs);
      await auth.saveToken(_token(
        access: AuthService.kTestAccessToken,
        refresh: AuthService.kTestRefreshToken,
      ));

      final client = _StubClient(401);
      final refreshed = await interceptorFor(auth, client).refreshAccessToken();

      expect(refreshed, isFalse, reason: 'the refresh still fails');
      expect(client.requestCount, 0, reason: 'a doomed refresh is not sent');
      expect(
        auth.currentToken,
        isNotNull,
        reason: 'clearing this token is what caused the login redirect loop',
      );
    });

    test('still clears a real session on 401', () async {
      final auth = AuthService(prefs);
      await auth.saveToken(_token(access: 'real-access', refresh: 'real-r'));

      final client = _StubClient(401);
      final refreshed = await interceptorFor(auth, client).refreshAccessToken();

      expect(refreshed, isFalse);
      expect(client.requestCount, 1);
      expect(
        auth.currentToken,
        isNull,
        reason: 'a genuinely revoked session must still log the user out',
      );
    });
  });
}
