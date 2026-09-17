import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';

/// Person id → display name, for the attribution line on a note row.
///
/// Derived rather than built inline in the list's `build()`. The map used to
/// be rebuilt from the full people list on every rebuild of the notes screen —
/// including rebuilds caused by something unrelated, like toggling the sort
/// order — even though it only changes when a person is added or renamed.
/// Riverpod caches this until the underlying stream re-emits.
final personNamesByIdProvider = Provider<Map<String, String>>((ref) {
  final people = ref.watch(peopleStreamProvider).valueOrNull;
  if (people == null) return const {};
  return {for (final person in people) person.id: person.name};
});

/// Folder id → folder name, for the folder chip on a note row.
///
/// Same reasoning as [personNamesByIdProvider].
final folderNamesByIdProvider = Provider<Map<String, String>>((ref) {
  final folders = ref.watch(foldersStreamProvider).valueOrNull;
  if (folders == null) return const {};
  return {for (final folder in folders) folder.id: folder.name};
});
