import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/sync/services/public_share_api_service.dart';

/// One block's most recent attribution — who last edited it and when.
///
/// Only populated when the editor is not the note's owner; owner-authored
/// edits surface no badge (we treat the owner as the implicit author).
class BlockAttribution {
  final String blockId;
  final String userId;
  final String displayName;
  final String username;
  final int serverTimestamp;
  final String operation;

  const BlockAttribution({
    required this.blockId,
    required this.userId,
    required this.displayName,
    required this.username,
    required this.serverTimestamp,
    required this.operation,
  });

  String get readableName {
    if (displayName.isNotEmpty) return displayName;
    if (username.isNotEmpty) return '@$username';
    return 'someone';
  }
}

/// Owner-facing activity feed for a note: the raw `NoteActivityEntry` list
/// from the server's `/v1/notes/:id/activity` endpoint. Surfaced for the
/// activity screen; the per-block derivation in
/// [noteBlockAttributionsProvider] is computed from the same source.
final noteActivityProvider =
    FutureProvider.family<List<NoteActivityEntry>, String>(
  (ref, noteId) async {
    final api = ref.watch(publicShareApiServiceProvider);
    return api.fetchNoteActivity(noteId);
  },
);

/// Derives a `Map<blockId, BlockAttribution>` of the most recent foreign
/// edit on each block of a note. "Foreign" means not by the viewing user
/// — their own edits are implicit and don't need a badge.
///
/// The activity feed endpoint is owner-only on the server today, so this
/// provider silently resolves to an empty map for non-owners. Keeping the
/// UI contract stable means the caller can unconditionally watch and just
/// render nothing when the data isn't available.
final noteBlockAttributionsProvider =
    FutureProvider.family<Map<String, BlockAttribution>, String>(
  (ref, noteId) async {
    final api = ref.watch(publicShareApiServiceProvider);
    final viewerUserId = ref.watch(currentUserIdProvider);

    List<NoteActivityEntry> entries;
    try {
      entries = await api.fetchNoteActivity(noteId, limit: 200);
    } catch (_) {
      // Non-owners hit 403; fall back to empty so the UI stays stable.
      return const <String, BlockAttribution>{};
    }

    final latestPerBlock = <String, BlockAttribution>{};
    for (final e in entries) {
      if (e.entityType != 'note_block') continue;
      if (e.userId == viewerUserId) continue;

      final existing = latestPerBlock[e.entityId];
      if (existing != null && existing.serverTimestamp >= e.serverTimestamp) {
        continue;
      }
      latestPerBlock[e.entityId] = BlockAttribution(
        blockId: e.entityId,
        userId: e.userId,
        displayName: e.displayName,
        username: e.username,
        serverTimestamp: e.serverTimestamp,
        operation: e.operation,
      );
    }
    return latestPerBlock;
  },
);
