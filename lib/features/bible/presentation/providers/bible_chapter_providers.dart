import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../data/bible_bookmark_repository.dart';
import '../../data/bible_highlight_repository.dart';
import '../../data/bible_verse_note_repository.dart';
import '../../domain/models/bible_highlight_entity.dart';
import '../../domain/models/bible_verse_note_entity.dart';

// =============================================================================
// Highlight providers
// =============================================================================

/// Bible highlight repository — synced CRUD for verse highlights.
final bibleHighlightRepositoryProvider =
    Provider<BibleHighlightRepository>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final userId = ref.watch(currentUserIdProvider);
  return BibleHighlightRepository(db, deviceId, userId);
});

/// Highlights for a specific chapter (reactive stream).
///
/// Keyed by (bookId, chapter) record. Rebuilds whenever highlights
/// are created, updated, or deleted for this chapter.
final chapterHighlightsProvider = StreamProvider.family<
    List<BibleHighlightEntity>,
    ({int bookId, int chapter})>((ref, params) {
  final repo = ref.watch(bibleHighlightRepositoryProvider);
  return repo.watchHighlightsForChapter(
    bookId: params.bookId,
    chapter: params.chapter,
  );
});

// =============================================================================
// Verse note providers
// =============================================================================

/// Notes written on verses ("Your notes" in the verse sheet).
final bibleVerseNoteRepositoryProvider =
    Provider<BibleVerseNoteRepository>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final userId = ref.watch(currentUserIdProvider);
  return BibleVerseNoteRepository(db, deviceId, userId);
});

/// The notes on one verse, newest first (reactive stream).
final verseNotesProvider = StreamProvider.family<List<BibleVerseNoteEntity>,
    ({int bookId, int chapter, int verse})>((ref, params) {
  return ref.watch(bibleVerseNoteRepositoryProvider).watchNotesForVerse(
        bookId: params.bookId,
        chapter: params.chapter,
        verse: params.verse,
      );
});

/// Every note written in a chapter, newest first (reactive stream). A note
/// covers verseStart..verseEnd, so a selection finds its notes by overlap.
final chapterVerseNotesProvider = StreamProvider.family<
    List<BibleVerseNoteEntity>, ({int bookId, int chapter})>((ref, params) {
  return ref.watch(bibleVerseNoteRepositoryProvider).watchNotesForChapter(
        bookId: params.bookId,
        chapter: params.chapter,
      );
});

/// The verses of a chapter that have at least one note (reactive stream), for
/// the marker beside them in the chapter list.
final chapterNotedVersesProvider = StreamProvider.family<Set<int>,
    ({int bookId, int chapter})>((ref, params) {
  return ref.watch(bibleVerseNoteRepositoryProvider).watchNotedVerses(
        bookId: params.bookId,
        chapter: params.chapter,
      );
});

// =============================================================================
// Bookmark providers
// =============================================================================

/// Bible bookmark repository — local-only CRUD for chapter bookmarks.
final bibleBookmarkRepositoryProvider =
    Provider<BibleBookmarkRepository>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  final userId = ref.watch(currentUserIdProvider);
  return BibleBookmarkRepository(db, userId);
});

/// All bookmarks for the current user (reactive stream).
final bibleBookmarksProvider =
    StreamProvider<List<BibleBookmarkEntry>>((ref) {
  return ref.watch(bibleBookmarkRepositoryProvider).watchBookmarks();
});
