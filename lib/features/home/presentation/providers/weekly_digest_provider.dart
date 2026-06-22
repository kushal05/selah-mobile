import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../data/services/weekly_digest_service.dart';
import '../../domain/models/weekly_digest.dart';

final weeklyDigestServiceProvider = Provider<WeeklyDigestService>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  return WeeklyDigestService(db);
});

/// 7-day digest for the current user. Invalidate to refetch.
final weeklyDigestProvider = FutureProvider<WeeklyDigest>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final service = ref.watch(weeklyDigestServiceProvider);
  return service.compute(userId: userId, days: 7);
});
