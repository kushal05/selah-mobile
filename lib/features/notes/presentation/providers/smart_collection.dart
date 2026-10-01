import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../l10n/l10n.dart';

/// A preset view of the notes list, chosen from the filter bar.
///
/// These were identified by their English names. "Recently Edited" was the
/// label on the chip, the heading over the list, the value held in state and
/// the case matched in visibleNotesProvider — all one string. Translating the
/// label would have changed the value and silently broken the match, which fell
/// through to a `_ => null` and showed every note. The identity is the enum
/// now, and the words are only ever looked up for display.
enum SmartCollection {
  recentlyEdited(Icons.history_rounded),
  untagged(Icons.label_off_rounded),
  stale(Icons.hourglass_empty_rounded);

  const SmartCollection(this.icon);

  final IconData icon;

  /// The name shown on the chip and as the list heading.
  String label(BuildContext context) {
    final t = l10n(context);
    return switch (this) {
      recentlyEdited => t.smartCollectionRecentlyEdited,
      untagged => t.smartCollectionUntagged,
      stale => t.smartCollectionStale,
    };
  }

  /// The ids of the notes in this collection, kept current as notes and tags
  /// change. Ids only: the screen already has the notes, and needs from here
  /// just which of them to show and how many there are. Exhaustive on purpose:
  /// a fourth collection will not compile until it says where its ids come
  /// from.
  AutoDisposeStreamProvider<List<String>> get noteIds => switch (this) {
    recentlyEdited => recentlyEditedNoteIdsProvider,
    untagged => untaggedNoteIdsProvider,
    stale => staleNoteIdsProvider,
  };
}
