import '../data/bible_database_service.dart';
import '../data/bible_version_state_repository.dart';
import '../data/bible_version_updates.dart';
import '../domain/models/bible_version_info.dart';

/// Downloads a Bible version.
///
/// Two screens need this and each has its own idea of how to show progress and
/// report failure — the versions screen uses a snackbar, the inline prompt
/// reports in place — but the operation itself is the same, and had been
/// written out twice. What is shared is the part that is easy to get subtly
/// wrong: which install path applies, and who becomes the default.
///
/// Callers go through `BibleDownloadManager`, which owns the state and the
/// dedupe; this is the operation it runs.
///
/// Throws on failure; the caller decides how to say so.
Future<void> downloadBibleVersion(
  BibleDatabaseService dbService,
  BibleVersionStateRepository repo,
  BibleVersionInfo info, {
  void Function(double progress)? onProgress,
  BibleVersionStamps? stamps,
  bool replace = false,
}) async {
  // Whether this is the first install or an added version is decided by the
  // service when the queued job runs, not here: with two downloads requested
  // before the first finishes, both would see a closed database.
  //
  // [replace] is an update: the installed verses are swapped for the new ones.
  // The ETag of what was installed is kept, to tell later whether the host has
  // a newer file.
  String? stamp;
  await dbService.install(
    info.code,
    info.downloadUrl,
    onProgress: onProgress,
    replace: replace,
    onStamp: (s) => stamp = s,
  );
  if (stamp != null) await stamps?.write(info.code, stamp!);

  // Whatever arrives first becomes the default, so the reader, notes and
  // search have a translation to use without the user choosing one.
  if (await repo.getDefaultCode() == null) {
    await repo.setDefault(info.code);
  }
}
