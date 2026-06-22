import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../data/repositories/memory_verse_repository.dart';
import '../../domain/models/memory_verse.dart';

final memoryVerseRepositoryProvider =
    Provider<MemoryVerseRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = MemoryVerseRepository(prefs);
  ref.onDispose(repo.dispose);
  return repo;
});

/// All memory verses ordered by next due date (soonest first).
final memoryVersesStreamProvider =
    StreamProvider<List<MemoryVerse>>((ref) {
  final repo = ref.watch(memoryVerseRepositoryProvider);
  return repo.watchAll().map((verses) {
    final sorted = List<MemoryVerse>.from(verses);
    sorted.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return sorted;
  });
});

/// Verses currently due for review (dueAt <= now).
final dueMemoryVersesProvider =
    FutureProvider<List<MemoryVerse>>((ref) async {
  final repo = ref.watch(memoryVerseRepositoryProvider);
  return repo.getDue();
});
