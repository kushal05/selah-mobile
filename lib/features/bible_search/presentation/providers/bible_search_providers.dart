import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bible/presentation/providers/bible_providers.dart';
import '../../data/bible_search_service.dart';

/// Bible search service — uses the pre-populated Bible SQLite database.
///
/// All FTS5 queries run inside [BibleSearchService]'s background isolate so
/// the UI thread is never blocked. The worker isolate is torn down when the
/// provider is disposed.
///
/// Completely separate from all other search providers.
final bibleSearchServiceProvider = Provider<BibleSearchService>((ref) {
  final dbService = ref.watch(bibleDatabaseServiceProvider);
  final service = BibleSearchService(dbService);
  ref.onDispose(service.dispose);
  return service;
});
