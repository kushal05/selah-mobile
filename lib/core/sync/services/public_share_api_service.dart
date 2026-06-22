import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/sync_config.dart';
import 'api_interceptor.dart';
import 'base_social_api_service.dart';

/// Metadata for a public share token returned by the list/create endpoints.
///
/// The plaintext token is only populated on the create response — never by
/// list. Callers must capture it at creation time since the server stores
/// only a hash.
class PublicShareToken {
  final String id;
  final String entityType;
  final String entityId;
  final String permission;
  final String createdBy;
  final int createdAt;
  final int? revokedAt;

  /// Plaintext token — present only on the create-token response.
  final String? token;

  const PublicShareToken({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.permission,
    required this.createdBy,
    required this.createdAt,
    this.revokedAt,
    this.token,
  });

  factory PublicShareToken.fromCreateJson(Map<String, dynamic> json) {
    return PublicShareToken(
      id: json['id'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      permission: json['permission'] as String,
      createdBy: '',
      createdAt: json['createdAt'] as int,
      token: json['token'] as String?,
    );
  }

  factory PublicShareToken.fromListJson(Map<String, dynamic> json) {
    return PublicShareToken(
      id: json['id'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      permission: json['permission'] as String,
      createdBy: json['createdBy'] as String? ?? '',
      createdAt: json['createdAt'] as int,
      revokedAt: json['revokedAt'] as int?,
    );
  }
}

/// One row in the owner-facing note activity feed.
class NoteActivityEntry {
  final String opId;
  final String entityType;
  final String entityId;
  final String operation;
  final int serverTimestamp;
  final String userId;
  final String displayName;
  final String username;

  const NoteActivityEntry({
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.serverTimestamp,
    required this.userId,
    required this.displayName,
    required this.username,
  });

  factory NoteActivityEntry.fromJson(Map<String, dynamic> json) {
    return NoteActivityEntry(
      opId: json['opId'] as String,
      entityType: json['entityType'] as String,
      entityId: json['entityId'] as String,
      operation: json['operation'] as String,
      serverTimestamp: json['serverTimestamp'] as int,
      userId: json['userId'] as String,
      displayName: json['displayName'] as String? ?? '',
      username: json['username'] as String? ?? '',
    );
  }
}

/// Read-only public note snapshot returned by the unauthenticated viewer
/// endpoint. Used by the deeplink handler when the app receives a public
/// share URL.
class PublicNoteSnapshot {
  final Map<String, dynamic> note;
  final List<Map<String, dynamic>> blocks;
  final int fetchedAt;

  const PublicNoteSnapshot({
    required this.note,
    required this.blocks,
    required this.fetchedAt,
  });

  factory PublicNoteSnapshot.fromJson(Map<String, dynamic> json) {
    return PublicNoteSnapshot(
      note: (json['note'] as Map).cast<String, dynamic>(),
      blocks: (json['blocks'] as List? ?? [])
          .map((b) => (b as Map).cast<String, dynamic>())
          .toList(),
      fetchedAt: json['fetchedAt'] as int,
    );
  }
}

/// API client for tokenised public share links.
///
/// Mirrors selah-api routes:
///   POST   /v1/shares/notes/:noteId/public-tokens   (auth)
///   GET    /v1/shares/notes/:noteId/public-tokens   (auth)
///   DELETE /v1/shares/public-tokens/:tokenId        (auth)
///   GET    /v1/public/notes/:token                  (no auth)
class PublicShareApiService {
  final SyncConfig config;
  final ApiInterceptor interceptor;

  PublicShareApiService({
    required this.config,
    required this.interceptor,
  });

  Uri _authed(String path) => Uri.parse('${config.apiBaseUrl}/v1/shares$path');
  Uri _public(String path) => Uri.parse('${config.apiBaseUrl}/v1/public$path');

  Map<String, String> get _authedHeaders => interceptor.headers();
  Map<String, String> get _publicHeaders => const {
        'Accept': 'application/json',
      };

  /// Generate a new public token for a note. The plaintext token is
  /// included in the response exactly once — capture it immediately.
  Future<PublicShareToken> createNoteToken(String noteId) async {
    await interceptor.ensureValidToken();
    final uri = _authed('/notes/$noteId/public-tokens');
    final response = await interceptor.post(uri, headers: _authedHeaders, body: null);
    _assertSuccess(response, 'Create public token');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PublicShareToken.fromCreateJson(body);
  }

  /// List active public tokens for a note (owner-only).
  Future<List<PublicShareToken>> listNoteTokens(String noteId) async {
    await interceptor.ensureValidToken();
    final uri = _authed('/notes/$noteId/public-tokens');
    final response = await interceptor.get(uri, headers: _authedHeaders);
    _assertSuccess(response, 'List public tokens');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = (body['tokens'] as List? ?? []).cast<Map<String, dynamic>>();
    return raw.map(PublicShareToken.fromListJson).toList();
  }

  /// Revoke a public token by id.
  Future<void> revokeToken(String tokenId) async {
    await interceptor.ensureValidToken();
    final uri = _authed('/public-tokens/$tokenId');
    final response = await interceptor.delete(uri, headers: _authedHeaders);
    _assertSuccess(response, 'Revoke public token');
  }

  /// Fetch the owner-facing activity feed for a note: recent ops on the
  /// note and its blocks, joined with the actor's profile.
  Future<List<NoteActivityEntry>> fetchNoteActivity(
    String noteId, {
    int limit = 50,
  }) async {
    await interceptor.ensureValidToken();
    final uri = Uri.parse(
      '${config.apiBaseUrl}/v1/notes/$noteId/activity?limit=$limit',
    );
    final response = await interceptor.get(uri, headers: _authedHeaders);
    _assertSuccess(response, 'Fetch note activity');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = (body['entries'] as List? ?? []).cast<Map<String, dynamic>>();
    return raw.map(NoteActivityEntry.fromJson).toList();
  }

  /// Resolve a plaintext public token to a note snapshot. No auth — used
  /// from deeplink handlers and the web viewer.
  Future<PublicNoteSnapshot> resolveNote(String token) async {
    final uri = _public('/notes/$token');
    final response = await http.get(uri, headers: _publicHeaders);
    _assertSuccess(response, 'Resolve public note');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PublicNoteSnapshot.fromJson(body);
  }

  void _assertSuccess(http.Response response, String operation) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      message = (body['message'] as String?) ??
          (body['error'] as String?) ??
          'HTTP ${response.statusCode}';
    } catch (_) {
      message = 'HTTP ${response.statusCode}';
    }
    throw SocialApiException(operation, response.statusCode, message);
  }
}
