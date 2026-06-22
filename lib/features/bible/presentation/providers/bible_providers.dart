import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../domain/models/bible_reference.dart';
import '../../data/bible_database_service.dart';
import '../../data/bible_repository.dart';
import '../../data/bible_version_api_service.dart';
import '../../data/bible_version_state_repository.dart';
import '../../domain/models/bible_book_entity.dart';
import '../../domain/models/bible_verse_entity.dart';
import '../../domain/models/bible_version_info.dart';
import '../../domain/services/verse_lookup_service.dart';

// =============================================================================
// Core service providers
// =============================================================================

/// Singleton Bible database service.
///
/// Initialized once at app startup via `ref.read(bibleDatabaseServiceProvider).init()`.
/// The service manages the lifecycle of the separate Bible SQLite file.
///
/// Uses [ChangeNotifierProvider] so that widgets and providers that call
/// `ref.watch(bibleDatabaseServiceProvider).isOpen` automatically rebuild
/// when [BibleDatabaseService.isOpen] transitions to true after a download.
final bibleDatabaseServiceProvider =
    ChangeNotifierProvider<BibleDatabaseService>((ref) {
  return BibleDatabaseService();
});

/// Bible repository — read-only query layer over the Bible SQLite database.
///
/// Completely isolated from the app's sync database. Does NOT participate
/// in global search or songs search.
final bibleRepositoryProvider = Provider<BibleRepository>((ref) {
  final dbService = ref.watch(bibleDatabaseServiceProvider);
  return BibleRepository(dbService);
});

/// Verse lookup service — resolves Bible references to verse text.
///
/// Used by the Notes editor to dynamically resolve verse text at render time.
final verseLookupServiceProvider = Provider<VerseLookupService>((ref) {
  final repo = ref.watch(bibleRepositoryProvider);
  return VerseLookupService(repo);
});

// =============================================================================
// Data providers for the Bible reference picker (selector flow)
// =============================================================================

/// All 66 books in canonical order.
/// Used by the book selector step of the Bible reference picker.
final bibleBooksProvider = Provider<List<BibleBookEntity>>((ref) {
  final repo = ref.watch(bibleRepositoryProvider);
  if (!ref.watch(bibleDatabaseServiceProvider).isOpen) return [];
  return repo.getAllBooks();
});

/// Old Testament books.
final bibleOldTestamentBooksProvider = Provider<List<BibleBookEntity>>((ref) {
  final repo = ref.watch(bibleRepositoryProvider);
  if (!ref.watch(bibleDatabaseServiceProvider).isOpen) return [];
  return repo.getBooksByTestament(0);
});

/// New Testament books.
final bibleNewTestamentBooksProvider = Provider<List<BibleBookEntity>>((ref) {
  final repo = ref.watch(bibleRepositoryProvider);
  if (!ref.watch(bibleDatabaseServiceProvider).isOpen) return [];
  return repo.getBooksByTestament(1);
});

/// Chapters available for a given (bookId, translation) pair.
/// Used by the chapter selector step.
///
/// Parameter: (bookId, translation) as a record.
final bibleChaptersProvider =
    Provider.family<List<int>, ({int bookId, String translation})>((ref, params) {
  final repo = ref.watch(bibleRepositoryProvider);
  if (!ref.watch(bibleDatabaseServiceProvider).isOpen) return [];
  return repo.getChapters(
    bookId: params.bookId,
    translation: params.translation,
  );
});

/// Verses for a given (bookId, chapter, translation) triple.
/// Used by the verse selector step.
///
/// Parameter: (bookId, chapter, translation) as a record.
final bibleVersesProvider = Provider.family<List<BibleVerseEntity>,
    ({int bookId, int chapter, String translation})>((ref, params) {
  final repo = ref.watch(bibleRepositoryProvider);
  if (!ref.watch(bibleDatabaseServiceProvider).isOpen) return [];
  return repo.getVerses(
    bookId: params.bookId,
    chapter: params.chapter,
    translation: params.translation,
  );
});

/// Available translations in the database.
final bibleTranslationsProvider = Provider<List<String>>((ref) {
  final repo = ref.watch(bibleRepositoryProvider);
  if (!ref.watch(bibleDatabaseServiceProvider).isOpen) return [];
  return repo.getAvailableTranslations();
});

/// Installed Bible versions as [BibleVersionInfo] objects, in registry order.
///
/// Derived from [bibleTranslationsProvider] — no extra tracking state.
final installedBibleVersionsProvider = Provider<List<BibleVersionInfo>>((ref) {
  final downloadedCodes =
      ref.watch(bibleTranslationsProvider).map((c) => c.toUpperCase()).toSet();
  final allVersions = ref.watch(bibleVersionStatesProvider).valueOrNull ?? [];
  return allVersions
      .where((v) => downloadedCodes.contains(v.code))
      .toList();
});

// =============================================================================
// Version state providers (local DB + server registry)
// =============================================================================

/// Repository for the local [BibleVersionStates] Drift table.
final bibleVersionStateRepositoryProvider =
    Provider<BibleVersionStateRepository>((ref) {
  return BibleVersionStateRepository(ref.watch(syncDatabaseProvider));
});

/// All available Bible versions from the local cache, ordered by sort_order.
/// Includes downloaded state derived from [bibleTranslationsProvider].
final bibleVersionStatesProvider =
    StreamProvider<List<BibleVersionInfo>>((ref) {
  final downloadedCodes =
      ref.watch(bibleTranslationsProvider).map((c) => c.toUpperCase()).toSet();
  return ref
      .watch(bibleVersionStateRepositoryProvider)
      .watchAll()
      .map((rows) => rows
          .map((row) => BibleVersionInfo.fromRow(
                row,
                isDownloaded: downloadedCodes.contains(row.code),
              ))
          .toList());
});

/// The code of the user's chosen default translation (e.g. 'NKJV').
/// Falls back to 'NKJV' if no default has been set yet.
final defaultBibleVersionProvider = Provider<String>((ref) {
  final versions = ref.watch(bibleVersionStatesProvider).valueOrNull ?? [];
  return versions.firstWhere((v) => v.isDefault, orElse: () {
    // Fallback: first downloaded version, then first available, then NKJV.
    final downloaded = versions.where((v) => v.isDownloaded).toList();
    if (downloaded.isNotEmpty) return downloaded.first;
    if (versions.isNotEmpty) return versions.first;
    return const BibleVersionInfo(
      code: kDefaultBibleVersionCode,
      name: 'New King James Version',
      downloadUrl: '',
      approximateSizeMb: 8,
      sortOrder: 0,
      isDefault: true,
      isDownloaded: false,
    );
  }).code;
});

/// API service for fetching version metadata from the backend.
final bibleVersionApiServiceProvider = Provider<BibleVersionApiService>((ref) {
  // Reads SyncConfig through the existing syncConfigProvider in sync_providers.
  final config = ref.watch(syncConfigProvider);
  return BibleVersionApiService(config: config);
});

// =============================================================================
// Verse lookup provider for rendering
// =============================================================================

/// Resolve a [BibleVerseReference] to verse text from the local database.
///
/// Returns a list of [BibleVerseText] for rendering. Empty list means the
/// verse is not available (triggers fallback UI).
///
/// This provider is keyed by the reference coordinates so each unique verse
/// block in a note gets its own cached result.
final verseLookupProvider =
    Provider.family<List<BibleVerseText>, BibleVerseReference>((ref, verseRef) {
  final lookupService = ref.watch(verseLookupServiceProvider);
  if (!ref.watch(bibleDatabaseServiceProvider).isOpen) return [];
  return lookupService.lookupVerses(verseRef);
});

// =============================================================================
// FTS5 search provider (Bible-only, NOT global search)
// =============================================================================

/// Search Bible verses using FTS5.
///
/// This is completely separate from global search and songs search.
/// Parameters: (query, translation) as a record.
final bibleSearchProvider = Provider.family<List<BibleVerseEntity>,
    ({String query, String? translation})>((ref, params) {
  final repo = ref.watch(bibleRepositoryProvider);
  if (!ref.watch(bibleDatabaseServiceProvider).isOpen) return [];
  if (params.query.trim().isEmpty) return [];
  return repo.searchVerses(
    query: params.query,
    translation: params.translation,
  );
});
