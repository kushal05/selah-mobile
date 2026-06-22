import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../domain/services/pray_today_service.dart';

/// Shared by the "Pray Today" screen and the home-screen "Today's Prayers"
/// widget so both render the identical set of due prayers.
final prayTodayServiceProvider = Provider<PrayTodayService>((ref) {
  return PrayTodayService(ref.watch(prayerRepositoryProvider));
});
