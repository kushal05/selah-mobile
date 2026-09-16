import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/bible_version_info.dart';
import 'providers/bible_providers.dart';

/// Downloads a Bible version.
///
/// Two screens need this and each has its own idea of how to show progress and
/// report failure — the versions screen uses a snackbar, the inline prompt
/// reports in place — but the operation itself is the same, and had been
/// written out twice. What is shared is the part that is easy to get subtly
/// wrong: which download call applies, and who becomes the default.
///
/// Throws on failure; the caller decides how to say so.
Future<void> downloadBibleVersion(
  WidgetRef ref,
  BibleVersionInfo info, {
  void Function(double progress)? onProgress,
}) async {
  final dbService = ref.read(bibleDatabaseServiceProvider);

  // The first version creates the Bible database file; every later one is
  // added to the database that is already open. Calling the wrong one of these
  // is the reason this lives in one place.
  if (!dbService.isOpen) {
    await dbService.download(info.downloadUrl, onProgress: onProgress);
  } else {
    await dbService.downloadVersion(info.code, info.downloadUrl,
        onProgress: onProgress);
  }

  // Whatever arrives first becomes the default, so the reader, notes and
  // search have a translation to use without the user choosing one.
  final repo = ref.read(bibleVersionStateRepositoryProvider);
  if (await repo.getDefaultCode() == null) {
    await repo.setDefault(info.code);
  }
}
