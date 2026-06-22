import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Authentication token data
class AuthToken {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String userId;

  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    required this.userId,
  });

  /// Check if token is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Check if token is about to expire (within 5 minutes)
  bool get isAboutToExpire =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  /// Create from JSON
  factory AuthToken.fromJson(Map<String, dynamic> json) {
    return AuthToken(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
      userId: json['userId'] as String,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'userId': userId,
      };
}

/// Service for managing authentication tokens
///
/// Handles token storage, refresh, and expiration.
class AuthService {
  static const _keyAuthToken = 'auth_token';
  static const _keyUserId = 'auth_user_id';

  final SharedPreferences _prefs;
  final _authStateController = StreamController<AuthToken?>.broadcast();

  AuthToken? _currentToken;

  AuthService(this._prefs) {
    _loadToken();
  }

  /// Stream of auth state changes
  Stream<AuthToken?> get authStateChanges => _authStateController.stream;

  /// Current auth token
  AuthToken? get currentToken => _currentToken;

  /// Current user ID
  String? get currentUserId => _currentToken?.userId;

  /// Check if user is authenticated
  bool get isAuthenticated => _currentToken != null && !_currentToken!.isExpired;

  /// Load token from storage
  void _loadToken() {
    final tokenJson = _prefs.getString(_keyAuthToken);
    if (tokenJson != null) {
      try {
        _currentToken = AuthToken.fromJson(
          jsonDecode(tokenJson) as Map<String, dynamic>,
        );
        _authStateController.add(_currentToken);
      } catch (_) {
        // Invalid token, clear it
        _prefs.remove(_keyAuthToken);
      }
    }
  }

  /// Save authentication token
  Future<void> saveToken(AuthToken token) async {
    _currentToken = token;
    await _prefs.setString(_keyAuthToken, jsonEncode(token.toJson()));
    await _prefs.setString(_keyUserId, token.userId);
    _authStateController.add(token);
  }

  /// Clear authentication (logout)
  Future<void> clearToken() async {
    _currentToken = null;
    await _prefs.remove(_keyAuthToken);
    await _prefs.remove(_keyUserId);
    _authStateController.add(null);
  }

  /// Get authorization header value
  String? getAuthorizationHeader() {
    if (_currentToken == null || _currentToken!.isExpired) {
      return null;
    }
    return 'Bearer ${_currentToken!.accessToken}';
  }

  /// Dispose resources
  void dispose() {
    _authStateController.close();
  }
}
