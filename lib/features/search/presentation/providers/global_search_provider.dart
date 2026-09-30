import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/models/person_model.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/models/promise_model.dart';
import '../../../../core/sync/models/song_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/sync/utils/sync_logger.dart';
import '../../../notes/domain/models/note.dart' as domain;
import '../../../notes/presentation/providers/database_provider.dart';

/// The five collections a global search reads, named so that a failure in one
/// of them can be reported rather than passed off as an empty result.
enum SearchArea { notes, prayers, promises, people, songs }

/// State for the global search screen.
class GlobalSearchState {
  final List<domain.Note> notes;
  final List<PrayerModel> prayers;
  final List<PromiseModel> promises;
  final List<PersonModel> people;
  final List<SongModel> songs;
  final bool isLoading;
  final bool hasSearched;

  /// The areas whose query threw. Their lists are empty here because they were
  /// never read, which is a different thing from having nothing to show, and
  /// the screen has to be able to tell the difference.
  final Set<SearchArea> failedAreas;

  const GlobalSearchState({
    this.notes = const [],
    this.prayers = const [],
    this.promises = const [],
    this.people = const [],
    this.songs = const [],
    this.isLoading = false,
    this.hasSearched = false,
    this.failedAreas = const {},
  });

  bool get hasResults =>
      notes.isNotEmpty ||
      prayers.isNotEmpty ||
      promises.isNotEmpty ||
      people.isNotEmpty ||
      songs.isNotEmpty;

  GlobalSearchState copyWith({
    List<domain.Note>? notes,
    List<PrayerModel>? prayers,
    List<PromiseModel>? promises,
    List<PersonModel>? people,
    List<SongModel>? songs,
    bool? isLoading,
    bool? hasSearched,
    Set<SearchArea>? failedAreas,
  }) {
    return GlobalSearchState(
      notes: notes ?? this.notes,
      prayers: prayers ?? this.prayers,
      promises: promises ?? this.promises,
      people: people ?? this.people,
      songs: songs ?? this.songs,
      isLoading: isLoading ?? this.isLoading,
      hasSearched: hasSearched ?? this.hasSearched,
      failedAreas: failedAreas ?? this.failedAreas,
    );
  }
}

/// Notifier that orchestrates parallel searches across all content types.
class GlobalSearchNotifier extends StateNotifier<GlobalSearchState> {
  final Ref _ref;

  GlobalSearchNotifier(this._ref) : super(const GlobalSearchState());

  /// Perform a search across all repositories in parallel.
  ///
  /// Each repository search is isolated — one failure does not affect others.
  Future<void> search(String query) async {
    state = state.copyWith(isLoading: true);

    final notesRepo = _ref.read(notesRepositoryProvider);
    final prayerRepo = _ref.read(prayerRepositoryProvider);
    final promiseRepo = _ref.read(promiseRepositoryProvider);
    final personRepo = _ref.read(personRepositoryProvider);
    final songRepo = _ref.read(songRepositoryProvider);
    final userId = _ref.read(currentUserIdProvider);

    // Start all searches in parallel
    // Song search covers title, lyrics content, AND tags
    final notesFuture = notesRepo.searchNotes(query);
    final prayersFuture = prayerRepo.searchPrayers(query, userId);
    final promisesFuture = promiseRepo.searchPromises(query, userId);
    final peopleFuture = personRepo.searchPeople(query, userId);
    final songsFuture = songRepo.searchSongs(query, userId);

    // Await each individually so one failure doesn't break all results
    List<domain.Note> notes = [];
    List<PrayerModel> prayers = [];
    List<PromiseModel> promises = [];
    List<PersonModel> people = [];
    List<SongModel> songs = [];

    // Each failure is recorded as well as logged. Swallowing it into an empty
    // list was how "No results found" came to cover a query that never ran —
    // the user reads that as "your note isn't here" and stops looking.
    final failed = <SearchArea>{};
    try {
      notes = await notesFuture;
    } catch (e) {
      failed.add(SearchArea.notes);
      SyncLogger.warning('[Search] notes query failed: $e');
    }
    try {
      prayers = await prayersFuture;
    } catch (e) {
      failed.add(SearchArea.prayers);
      SyncLogger.warning('[Search] prayers query failed: $e');
    }
    try {
      promises = await promisesFuture;
    } catch (e) {
      failed.add(SearchArea.promises);
      SyncLogger.warning('[Search] promises query failed: $e');
    }
    try {
      people = await peopleFuture;
    } catch (e) {
      failed.add(SearchArea.people);
      SyncLogger.warning('[Search] people query failed: $e');
    }
    try {
      songs = await songsFuture;
    } catch (e) {
      failed.add(SearchArea.songs);
      SyncLogger.warning('[Search] songs query failed: $e');
    }

    // Only update state if the notifier is still mounted
    if (!mounted) return;
    state = GlobalSearchState(
      notes: notes,
      prayers: prayers,
      promises: promises,
      people: people,
      songs: songs,
      isLoading: false,
      hasSearched: true,
      failedAreas: failed,
    );
  }

  /// Clear all search results and reset to initial state.
  void clear() {
    state = const GlobalSearchState();
  }
}

final globalSearchProvider =
    StateNotifierProvider<GlobalSearchNotifier, GlobalSearchState>((ref) {
  return GlobalSearchNotifier(ref);
});
