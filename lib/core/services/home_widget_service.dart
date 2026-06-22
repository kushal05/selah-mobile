import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

/// iOS App Group identifier. MUST match the App Group capability configured on
/// the Runner target and the WidgetKit extension target (see
/// `ios/SelahWidget/README_SETUP.md`). Ignored on Android.
const String kWidgetAppGroupId = 'group.in.selahapp.app';

/// Handles taps on home-screen widgets.
///
/// A tapped widget launches the app with a `selah://widget/...` URI. The
/// `home_widget` plugin surfaces that URI on cold start
/// ([HomeWidget.initiallyLaunchedFromHomeWidget]) and on warm start
/// ([HomeWidget.widgetClicked]); we translate it to an in-app GoRouter path and
/// navigate. Mirrors the structure of
/// `DeepLinkService` (which handles the HTTPS App Links).
class HomeWidgetService {
  HomeWidgetService({required GoRouter router}) : _router = router;

  final GoRouter _router;
  StreamSubscription<Uri?>? _subscription;
  bool _initialized = false;

  /// Safe to call multiple times — only the first call takes effect.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await HomeWidget.setAppGroupId(kWidgetAppGroupId);
    } catch (e) {
      debugPrint('HomeWidgetService: setAppGroupId failed: $e');
    }

    // Cold start: the app was launched by tapping a widget.
    try {
      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initialUri != null) {
        // Let the router settle (splash → auth check) before navigating.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('HomeWidgetService: initial widget uri failed: $e');
    }

    // Warm start: a widget was tapped while the app is already running.
    _subscription = HomeWidget.widgetClicked.listen(
      (uri) {
        if (uri != null) _handleUri(uri);
      },
      onError: (e) {
        debugPrint('HomeWidgetService: click stream error: $e');
      },
    );
  }

  void _handleUri(Uri uri) {
    final path = widgetUriToAppPath(uri);
    if (path != null) {
      debugPrint('HomeWidgetService: navigating to $path');
      _router.go(path);
    }
  }

  /// Maps a `selah://widget/...` URI (emitted by a tapped widget) to an in-app
  /// GoRouter path. Returns null for anything unrecognized.
  ///
  /// Supported forms (kept in sync with the native widgets' click URIs):
  ///   `selah://widget/notes/new`      → `/notes/new`
  ///   `selah://widget/note?id=<id>`   → `/notes/<id>`
  ///   `selah://widget/prayers/new`    → `/prayers/new`
  ///   `selah://widget/prayer?id=<id>` → `/prayers/<id>`
  ///   `selah://widget/log-prayer?id=<id>` → `/prayers/today?log=<id>`
  ///   `selah://widget/pray-today`     → `/prayers/today`
  ///   `selah://widget/songs`          → `/songs`
  ///
  /// Also used by the GoRouter redirect, since Flutter's platform deep-link
  /// handling can forward the raw widget URI to the router directly.
  static String? widgetUriToAppPath(Uri uri) {
    if (uri.scheme != 'selah') return null;

    // Normalize: host is usually 'widget'; fold any non-'widget' host in as a
    // leading segment so both selah://widget/x and selah://x/... work.
    final segments = <String>[
      if (uri.host.isNotEmpty && uri.host != 'widget') uri.host,
      ...uri.pathSegments,
    ].where((s) => s.isNotEmpty).toList();

    if (segments.isNotEmpty && segments.first == 'widget') {
      segments.removeAt(0);
    }
    if (segments.isEmpty) return null;

    final id = uri.queryParameters['id'];

    switch (segments.first) {
      case 'notes':
        return (segments.length >= 2 && segments[1] == 'new')
            ? '/notes/new'
            : '/notes';
      case 'note':
        return (id != null && id.isNotEmpty) ? '/notes/$id' : '/notes';
      case 'prayers':
        return (segments.length >= 2 && segments[1] == 'new')
            ? '/prayers/new'
            : '/prayers';
      case 'prayer':
        return (id != null && id.isNotEmpty) ? '/prayers/$id' : '/prayers';
      case 'log-prayer':
        return (id != null && id.isNotEmpty)
            ? '/prayers/today?log=$id'
            : '/prayers/today';
      case 'pray-today':
        return '/prayers/today';
      case 'songs':
        return '/songs';
      default:
        return null;
    }
  }

  void dispose() {
    _subscription?.cancel();
  }
}
