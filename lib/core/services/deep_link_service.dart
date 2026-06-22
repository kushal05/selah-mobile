import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Handles incoming deep links (App Links / Universal Links) and routes them
/// through GoRouter. Supports both cold-start (initial link) and warm-start
/// (link received while app is running).
class DeepLinkService {
  DeepLinkService({required GoRouter router}) : _router = router;

  final GoRouter _router;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;
  bool _initialized = false;

  /// The deep link host that the app handles.
  static const String deepLinkHost = 'selahapp.in';

  /// Initialize the service: check for an initial link and listen for
  /// subsequent links while the app is in the foreground.
  ///
  /// Safe to call multiple times — only the first call takes effect.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _appLinks = AppLinks();

    // Handle the initial link (cold start from a deep link).
    // Delay slightly to ensure the router and auth state are ready,
    // avoiding a race where we call go() before redirect can evaluate.
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        // Allow the router to settle (splash → auth check) before navigating.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('DeepLinkService: Failed to get initial link: $e');
    }

    // Listen for links while the app is running (warm start).
    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) {
        debugPrint('DeepLinkService: Link stream error: $e');
      },
    );
  }

  /// Convert an incoming URI to an in-app path and navigate via GoRouter.
  void _handleUri(Uri uri) {
    final path = uriToAppPath(uri);
    if (path != null) {
      debugPrint('DeepLinkService: Navigating to $path');
      _router.go(path);
    }
  }

  /// Maps an external deep link URI to an in-app GoRouter path.
  ///
  /// Only handles HTTPS App Links: `https://selahapp.in/notes/abc-123`
  ///
  /// Special case: Bible links use path-based format externally
  /// (`/bible/1/3?t=KJV&v=16`) but query-param format internally
  /// (`/bible/chapter?bookId=1&chapter=3&translation=KJV&verse=16`).
  @visibleForTesting
  static String? uriToAppPath(Uri uri) {
    // Only handle HTTPS links for our domain.
    if (uri.scheme != 'https' || uri.host != deepLinkHost) return null;

    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;

    // Bible path adapter: /bible/{bookId}/{chapter}?t=&v=
    // → /bible/chapter?bookId=&chapter=&translation=&verse=
    if (segments.length >= 3 && segments[0] == 'bible') {
      final bookId = int.tryParse(segments[1]);
      final chapter = int.tryParse(segments[2]);
      if (bookId == null || chapter == null) return null;

      final translation = uri.queryParameters['t'] ?? 'KJV';
      final verseStr = uri.queryParameters['v'];
      final verse = verseStr != null ? int.tryParse(verseStr) : null;
      var path = '/bible/chapter?bookId=$bookId&chapter=$chapter'
          '&translation=$translation';
      if (verse != null && verse > 0) path += '&verse=$verse';
      return path;
    }

    // All other paths map directly: the external URL path matches the
    // GoRouter path (e.g., /notes/{id}, /prayers/{id}, /social/groups/{id}).
    final path = uri.path;
    final query = uri.query;
    return query.isNotEmpty ? '$path?$query' : path;
  }

  void dispose() {
    _subscription?.cancel();
  }
}
