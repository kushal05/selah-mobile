import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../prayers/presentation/providers/pray_today_provider.dart';
import '../../data/services/widget_data_publisher.dart';

/// Publishes home-screen widget data. Callers depend only on this provider so
/// the storage backend stays a one-file concern.
final widgetDataPublisherProvider = Provider<WidgetDataPublisher>((ref) {
  return WidgetDataPublisher(
    noteRepo: ref.watch(noteRepositoryProvider),
    noteBlockRepo: ref.watch(noteBlockRepositoryProvider),
    prayerRepo: ref.watch(prayerRepositoryProvider),
    prayTodayService: ref.watch(prayTodayServiceProvider),
  );
});
