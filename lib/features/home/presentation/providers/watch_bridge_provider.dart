import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../prayers/presentation/providers/prayer_streak_provider.dart';
import '../../data/services/watch_bridge_service.dart';

final watchBridgeServiceProvider =
    Provider<WatchBridgeService>((ref) {
  return WatchBridgeService(
    db: ref.watch(syncDatabaseProvider),
    streakService: ref.watch(prayerStreakServiceProvider),
  );
});
