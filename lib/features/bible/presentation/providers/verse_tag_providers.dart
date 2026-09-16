import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/models/note_block_model.dart'
    show BlockType, NoteBlockModel;
import '../../../../core/sync/providers/sync_providers.dart';
import '../../domain/models/bible_reference.dart';
import 'bible_providers.dart';

/// A verse, as anything stored per-verse keys it.
///
/// `(bookId, chapter, verse)` rather than a name: book names are abbreviated
/// and localised, and already need fuzzy resolution in two places, so they
/// make a poor key. This matches what bible_highlights uses.
typedef VerseKey = ({int bookId, int chapter, int verse});

/// Tags that the user's notes have put on verses, keyed by verse.
///
/// Verse tags live on Bible reference blocks, so this reads them back out —
/// the reverse of the direction the editor writes them. It is a whole-library
/// scan, which is affordable because it is over Bible reference blocks only
/// and is rebuilt just when one of them changes.
///
/// A verse tagged from two different notes carries both tags, which is what
/// "shown as a union" means: the reading view answers "what have I called this
/// verse", not "what did that one note call it".
/// Identifies a set of blocks by what this index actually depends on.
///
/// Drift re-runs a watched query on any write to the table, so typing in an
/// unrelated note re-emitted the whole Bible-reference list — measured at one
/// emission per keystroke-pause save. The rows are identical in that case, and
/// comparing this is far cheaper than decoding every block's JSON again.
String _signature(List<NoteBlockModel> blocks) {
  final parts = [
    for (final b in blocks) '${b.id}\u0001${b.content['text']}',
  ]..sort();
  return parts.join('\u0000');
}

/// autoDispose: this is a whole-library scan, and it should stop costing
/// anything the moment the reader is closed. Without it the subscription
/// outlived the screen and kept re-indexing for the rest of the session.
final verseTagsProvider =
    StreamProvider.autoDispose<Map<VerseKey, Set<String>>>((ref) {
  final blockRepo = ref.watch(noteBlockRepositoryProvider);
  final lookup = ref.watch(verseLookupServiceProvider);
  // The Bible database supplies book-name resolution; with none open there is
  // nothing to key against.
  final isOpen = ref.watch(bibleDatabaseServiceProvider).isOpen;

  return blockRepo
      .watchBlocksOfType(BlockType.bibleReference)
      .distinct((a, b) => _signature(a) == _signature(b))
      .map((blocks) {
    final index = <VerseKey, Set<String>>{};
    if (!isOpen) return index;

    for (final block in blocks) {
      final raw = block.content['text'];
      if (raw is! String || raw.isEmpty) continue;

      final BibleReference reference;
      try {
        reference =
            BibleReference.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // A block whose JSON will not parse contributes nothing rather than
        // taking the whole index down with it.
        continue;
      }
      if (reference.tagIds.isEmpty) continue;

      final bookId = lookup.resolveBookId(reference.reference.book);
      if (bookId == null) continue;

      for (final verse in reference.reference.verses) {
        final key = (
          bookId: bookId,
          chapter: reference.reference.chapter,
          verse: verse,
        );
        index.putIfAbsent(key, () => <String>{}).addAll(reference.tagIds);
      }
    }
    return index;
  });
});

/// Tags on the verses of one chapter, ready for the reader to look up per row.
final chapterVerseTagsProvider = Provider.autoDispose
    .family<Map<int, Set<String>>, ({int bookId, int chapter})>((ref, params) {
  final all = ref.watch(verseTagsProvider).valueOrNull;
  if (all == null) return const {};

  final forChapter = <int, Set<String>>{};
  for (final entry in all.entries) {
    if (entry.key.bookId != params.bookId) continue;
    if (entry.key.chapter != params.chapter) continue;
    forChapter[entry.key.verse] = entry.value;
  }
  return forChapter;
});
