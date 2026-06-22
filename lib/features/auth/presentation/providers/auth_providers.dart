import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/sync/services/auth_service.dart';
import '../../../../core/sync/utils/sync_logger.dart';

/// Provider that streams auth state changes
final authStateProvider = StreamProvider<AuthToken?>((ref) async* {
  final authService = ref.watch(authServiceProvider);
  yield authService.currentToken;
  yield* authService.authStateChanges;
});

/// Whether the user is currently authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenOrNull(data: (token) => token != null && !token.isExpired) ?? false;
});

/// Login request model
class LoginRequest {
  final String email;
  final String password;
  final String? deviceId;
  final String? deviceName;
  final String? platform;

  const LoginRequest({
    required this.email,
    required this.password,
    this.deviceId,
    this.deviceName,
    this.platform,
  });
}

/// Register request model
class RegisterRequest {
  final String name;
  final String email;
  final String password;
  final String? deviceName;
  final String? platform;

  const RegisterRequest({
    required this.name,
    required this.email,
    required this.password,
    this.deviceName,
    this.platform,
  });
}

/// Auth action notifier for login/register/logout
class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  AuthNotifier(this._ref) : super(const AsyncValue.data(null));

  /// Read the persisted device ID directly from SharedPreferences.
  /// This avoids relying on [deviceIdProvider] which may still hold the
  /// default value before sync initialization completes.
  ///
  /// On first-ever launch, generates a UUID and persists it so that
  /// [SyncService._getOrCreateDeviceId] finds and reuses the same ID.
  Future<String> _resolveDeviceId() async {
    final prefs = _ref.read(sharedPreferencesProvider);
    final stored = prefs.getString('sync_device_id');
    if (stored != null && stored.isNotEmpty) return stored;

    // First launch: generate, persist, and propagate a device ID
    final newId = 'device_${const Uuid().v4()}';
    await prefs.setString('sync_device_id', newId);
    _ref.read(deviceIdProvider.notifier).state = newId;
    return newId;
  }

  static String _defaultPlatform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'unknown';
    }
  }

  static String _defaultDeviceName() {
    final p = _defaultPlatform();
    return '${p[0].toUpperCase()}${p.substring(1)} Device';
  }

  Future<bool> login(LoginRequest request) async {
    state = const AsyncValue.loading();
    try {
      final config = _ref.read(syncConfigProvider);
      final interceptor = _ref.read(apiInterceptorProvider);
      final resolvedDeviceId = request.deviceId ?? await _resolveDeviceId();
      final response = await interceptor.post(
        Uri.parse('${config.apiBaseUrl}/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': request.email,
          'password': request.password,
          'deviceId': resolvedDeviceId,
          'deviceName': request.deviceName ?? _defaultDeviceName(),
          'platform': request.platform ?? _defaultPlatform(),
        }),
        timeout: config.httpTimeout,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tokens = data['tokens'] as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>;

        final authToken = AuthToken(
          accessToken: tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String?,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(tokens['expiresAt'] as int),
          userId: user['id'] as String,
        );

        final authService = _ref.read(authServiceProvider);
        await authService.saveToken(authToken);

        // Update current user ID
        _ref.read(currentUserIdProvider.notifier).state = authToken.userId;

        // Check profile completeness from the server response first,
        // so it works even on a fresh device with no local DB data.
        final serverUsername = (user['username'] as String?)?.trim() ?? '';
        final serverDisplayName = (user['displayName'] as String?)?.trim() ?? '';
        final isCompleteFromServer =
            serverUsername.isNotEmpty && serverDisplayName.isNotEmpty;
        _ref.read(profileCompleteProvider.notifier).state = isCompleteFromServer;

        // Kick off post-login sync in the background — server already
        // returned profile completeness inline, so we don't block nav.
        // ignore: discarded_futures
        _runPostLoginSync('login');

        state = const AsyncValue.data(null);
        return true;
      } else {
        String message;
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          message = data['message'] as String? ?? 'Login failed';
        } catch (_) {
          message = 'Server error (${response.statusCode})';
        }
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      }
    } catch (e, st) {
      final message = e is TypeError ? 'Unexpected server response' : e.toString();
      state = AsyncValue.error(message, st);
      return false;
    }
  }

  Future<bool> register(RegisterRequest request) async {
    state = const AsyncValue.loading();
    try {
      final config = _ref.read(syncConfigProvider);
      final interceptor = _ref.read(apiInterceptorProvider);
      final resolvedDeviceId = await _resolveDeviceId();
      final response = await interceptor.post(
        Uri.parse('${config.apiBaseUrl}/v1/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': request.name,
          'email': request.email,
          'password': request.password,
          'deviceId': resolvedDeviceId,
          'deviceName': request.deviceName ?? _defaultDeviceName(),
          'platform': request.platform ?? _defaultPlatform(),
        }),
        timeout: config.httpTimeout,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tokens = data['tokens'] as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>;

        final authToken = AuthToken(
          accessToken: tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String?,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(tokens['expiresAt'] as int),
          userId: user['id'] as String,
        );

        final authService = _ref.read(authServiceProvider);
        await authService.saveToken(authToken);

        _ref.read(currentUserIdProvider.notifier).state = authToken.userId;

        // Check profile completeness from the server response first.
        final serverUsername = (user['username'] as String?)?.trim() ?? '';
        final serverDisplayName = (user['displayName'] as String?)?.trim() ?? '';
        final isCompleteFromServer =
            serverUsername.isNotEmpty && serverDisplayName.isNotEmpty;
        _ref.read(profileCompleteProvider.notifier).state = isCompleteFromServer;

        // Kick off post-register sync in the background.
        // ignore: discarded_futures
        _runPostLoginSync('register');

        state = const AsyncValue.data(null);
        return true;
      } else {
        String message;
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          message = data['message'] as String? ?? 'Registration failed';
        } catch (_) {
          message = 'Server error (${response.statusCode})';
        }
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      }
    } catch (e, st) {
      final message = e is TypeError ? 'Unexpected server response' : e.toString();
      state = AsyncValue.error(message, st);
      return false;
    }
  }

  Future<bool> loginWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      // 1. Trigger Google Sign-In flow
      // serverClientId is the **Web** client ID from Google Cloud Console.
      // It tells the SDK to request an ID token (not just an access token).
      final googleSignIn = GoogleSignIn(
        serverClientId: AppConfig.googleServerClientId.isNotEmpty
            ? AppConfig.googleServerClientId
            : null,
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        // User cancelled
        state = const AsyncValue.data(null);
        return false;
      }

      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        state = AsyncValue.error('Failed to get Google ID token', StackTrace.current);
        return false;
      }

      // 2. Send ID token to backend
      final config = _ref.read(syncConfigProvider);
      final interceptor = _ref.read(apiInterceptorProvider);
      final resolvedDeviceId = await _resolveDeviceId();
      final response = await interceptor.post(
        Uri.parse('${config.apiBaseUrl}/v1/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'idToken': idToken,
          'deviceId': resolvedDeviceId,
          'deviceName': _defaultDeviceName(),
          'platform': _defaultPlatform(),
        }),
        timeout: config.httpTimeout,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tokens = data['tokens'] as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>;

        final authToken = AuthToken(
          accessToken: tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String?,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(tokens['expiresAt'] as int),
          userId: user['id'] as String,
        );

        final authService = _ref.read(authServiceProvider);
        await authService.saveToken(authToken);

        _ref.read(currentUserIdProvider.notifier).state = authToken.userId;

        // Check profile completeness from server response
        final serverUsername = (user['username'] as String?)?.trim() ?? '';
        final serverDisplayName = (user['displayName'] as String?)?.trim() ?? '';
        final isCompleteFromServer =
            serverUsername.isNotEmpty && serverDisplayName.isNotEmpty;
        _ref.read(profileCompleteProvider.notifier).state = isCompleteFromServer;

        // Kick off post-login sync in the background. We deliberately do
        // NOT await this — the server already returned profile completeness
        // inline (username/displayName), so navigation to home can proceed
        // immediately. Home-screen providers will surface their own
        // loading states while sync pulls remote data.
        // ignore: discarded_futures
        _runPostLoginSync('google');

        state = const AsyncValue.data(null);
        return true;
      } else {
        String message;
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          message = data['message'] as String? ?? 'Google login failed';
        } catch (_) {
          message = 'Server error (${response.statusCode})';
        }
        state = AsyncValue.error(message, StackTrace.current);
        return false;
      }
    } catch (e, st) {
      final message = e is TypeError ? 'Unexpected server response' : e.toString();
      state = AsyncValue.error(message, st);
      return false;
    }
  }

  /// Runs initial sync after a successful login/register without blocking
  /// the caller. The auth response already contains profile completeness
  /// info, so navigation can proceed immediately while sync pulls account
  /// data in the background. Errors are logged but never propagated.
  Future<void> _runPostLoginSync(String origin) async {
    try {
      final syncService = await _ref.read(syncServiceProvider.future);
      if (!syncService.isInitialized) {
        await syncService.initialize();
      }
      final result = await syncService.syncNow();
      SyncLogger.info(
        'Post-$origin sync: success=${result.success}, '
        'pushed=${result.operationsPushed}, '
        'pulled=${result.operationsPulled}, '
        'conflicts=${result.conflictsResolved}',
      );
    } catch (e, st) {
      SyncLogger.error('Post-$origin sync failed', e, st);
    }
  }

  Future<void> logout() async {
    try {
      final authService = _ref.read(authServiceProvider);
      final config = _ref.read(syncConfigProvider);
      final interceptor = _ref.read(apiInterceptorProvider);
      final deviceId = _ref.read(deviceIdProvider);
      final refreshToken = authService.currentToken?.refreshToken;

      // Server-side revocation (best-effort, don't block logout on failure)
      try {
        final authHeader = authService.getAuthorizationHeader();
        await interceptor.post(
          Uri.parse('${config.apiBaseUrl}/v1/auth/logout'),
          headers: {
            'Content-Type': 'application/json',
            if (authHeader != null) 'Authorization': authHeader,
          },
          body: jsonEncode({
            if (refreshToken != null) 'refreshToken': refreshToken,
            'deviceId': deviceId,
          }),
          timeout: config.httpTimeout,
        );
      } catch (_) {
        // Best-effort: logout should always succeed locally
      }

      // Clear all local user data and reset sync cursor so the next
      // login starts with a fresh pull from the server.
      final db = _ref.read(syncDatabaseProvider);
      await db.clearAllUserData();
      await authService.clearToken();
    } catch (e) {
      debugPrint('Logout cleanup failed: $e');
    }
    _ref.read(currentUserIdProvider.notifier).state = 'default-user-id';
    _ref.read(profileCompleteProvider.notifier).state = null;
    state = const AsyncValue.data(null);
  }

  Future<bool> forgotPassword(String email) async {
    state = const AsyncValue.loading();
    try {
      final config = _ref.read(syncConfigProvider);
      final interceptor = _ref.read(apiInterceptorProvider);
      final response = await interceptor.post(
        Uri.parse('${config.apiBaseUrl}/v1/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
        timeout: config.httpTimeout,
      );

      state = const AsyncValue.data(null);
      return response.statusCode == 200;
    } catch (e, st) {
      state = AsyncValue.error(e.toString(), st);
      return false;
    }
  }

  /// Check if an email is already registered.
  /// Returns an error message if taken, or null if available.
  Future<String?> checkEmailAvailability(String email) async {
    try {
      final config = _ref.read(syncConfigProvider);
      final interceptor = _ref.read(apiInterceptorProvider);
      final response = await interceptor.get(
        Uri.parse('${config.apiBaseUrl}/v1/auth/check-email?email=${Uri.encodeComponent(email)}'),
        headers: {'Content-Type': 'application/json'},
        timeout: config.httpTimeout,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final available = data['available'] as bool? ?? true;
        return available ? null : 'This email is already registered';
      }
      return null; // On unexpected status, don't block the user
    } catch (_) {
      return null; // On network error, don't block the user
    }
  }

  /// Check if a username is already taken.
  /// Returns an error message if taken, or null if available.
  Future<String?> checkUsernameAvailability(String username) async {
    try {
      final config = _ref.read(syncConfigProvider);
      final interceptor = _ref.read(apiInterceptorProvider);
      final response = await interceptor.get(
        Uri.parse('${config.apiBaseUrl}/v1/auth/check-username?username=${Uri.encodeComponent(username)}'),
        headers: {'Content-Type': 'application/json'},
        timeout: config.httpTimeout,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final available = data['available'] as bool? ?? true;
        return available ? null : 'This username is already taken';
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// Provider for auth actions
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
  return AuthNotifier(ref);
});
