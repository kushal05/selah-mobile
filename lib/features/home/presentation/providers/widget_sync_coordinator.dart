import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import 'widget_data_provider.dart';

/// Keeps the home-screen widgets in step with the local database.
///
/// Listens to the notes and active-prayers streams and republishes the widget
/// payloads (debounced) whenever they change, so a note/prayer created or
/// edited in-app is reflected on the home screen the next time the OS samples
/// the widget. Activated by `ref.watch(widgetSyncCoordinatorProvider)` in
/// `appRouterProvider`, alongside the other long-lived watchers.
class WidgetSyncCoordinator {
  WidgetSyncCoordinator(this._ref);

  final Ref _ref;
  Timer? _debounce;
  final List<ProviderSubscription<dynamic>> _subs = [];

  static const _debounceDelay = Duration(milliseconds: 600);

  void start() {
    // The authenticated user id is only known after sync init completes
    // (it starts as 'default-user-id'). Publishing is a no-op until then, so
    // republish the moment it resolves — otherwise the first real payload
    // would only land on the next note/prayer edit.
    _subs.add(_ref.listen(currentUserIdProvider, (_, _) => _schedule()));
    _subs.add(_ref.listen(syncNotesStreamProvider, (_, _) => _schedule()));
    _subs.add(
      _ref.listen(activePrayersStreamProvider, (_, _) => _schedule()),
    );
  }

  /// Publish immediately (used on startup and on app pause).
  void publishNow() => _publish();

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _publish);
  }

  void _publish() {
    final userId = _ref.read(currentUserIdProvider);
    // ignore: discarded_futures
    _ref.read(widgetDataPublisherProvider).publishAll(userId: userId);
  }

  void dispose() {
    _debounce?.cancel();
    for (final sub in _subs) {
      sub.close();
    }
    _subs.clear();
  }
}

final widgetSyncCoordinatorProvider = Provider<WidgetSyncCoordinator>((ref) {
  final coordinator = WidgetSyncCoordinator(ref);
  coordinator.start();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
