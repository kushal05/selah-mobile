import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/sync_database.dart';
import '../../../../core/sync/providers/sync_providers.dart';

/// Notification ID base for feedback messages (range 90000–90999)
const _feedbackNotificationIdBase = 90000;

/// Provider that polls for new admin feedback messages and triggers
/// a local notification when one arrives via sync.
///
/// Design: watches a single DB query for the most recent admin message,
/// compares its ID against the last-seen ID, and fires a notification
/// when it changes. This avoids per-thread listeners and listener leaks.
final feedbackNotificationWatcherProvider = Provider.autoDispose<void>((ref) {
  final db = ref.watch(syncDatabaseProvider);

  String? lastSeenAdminMessageId;

  // Watch for the latest admin message across all threads
  final query = db.select(db.feedbackMessages)
    ..where((m) => m.deleted.equals(0))
    ..where((m) => m.senderType.equals('admin'))
    ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
    ..limit(1);

  final subscription = query.watch().listen((rows) {
    if (rows.isEmpty) return;

    final latest = rows.first;

    // Skip first emission (existing data on app launch)
    if (lastSeenAdminMessageId == null) {
      lastSeenAdminMessageId = latest.id;
      return;
    }

    // New admin message arrived
    if (latest.id != lastSeenAdminMessageId) {
      lastSeenAdminMessageId = latest.id;
      _showAdminReplyNotification(ref, latest.threadId, db);
    }
  });

  ref.onDispose(() => subscription.cancel());
});

Future<void> _showAdminReplyNotification(
  Ref ref,
  String threadId,
  SyncDatabase db,
) async {
  try {
    // Look up the thread subject for the notification body
    final thread = await (db.select(db.feedbackThreads)
          ..where((t) => t.id.equals(threadId)))
        .getSingleOrNull();

    final subject = thread?.subject ?? 'your feedback';

    final notificationService = ref.read(notificationServiceProvider);
    await notificationService.showNotification(
      id: _feedbackNotificationIdBase + (threadId.hashCode % 1000).abs(),
      title: 'Support replied to your feedback',
      body: subject,
    );
  } catch (_) {
    // Best-effort: notification failure should never block sync
  }
}
