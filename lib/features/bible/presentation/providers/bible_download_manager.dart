import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/bible_database_service.dart';
import '../../domain/models/bible_version_info.dart';
import '../bible_download_action.dart';
import 'bible_providers.dart';

enum BibleDownloadStatus { queued, downloading, installing, done, failed }

/// Progress of one Bible version download.
class BibleDownloadState {
  final String code;
  final String name;
  final BibleDownloadStatus status;

  /// 0..1 while [BibleDownloadStatus.downloading].
  final double progress;
  final Object? error;

  const BibleDownloadState({
    required this.code,
    required this.name,
    required this.status,
    this.progress = 0,
    this.error,
  });

  /// Queued, downloading or installing.
  bool get isActive =>
      status == BibleDownloadStatus.queued ||
      status == BibleDownloadStatus.downloading ||
      status == BibleDownloadStatus.installing;

  BibleDownloadState copyWith({
    BibleDownloadStatus? status,
    double? progress,
    Object? error,
  }) =>
      BibleDownloadState(
        code: code,
        name: name,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        error: error,
      );
}

/// Runs one download. Overridable so tests can use a fake instead of the
/// network and the Bible database.
typedef BibleDownloadRunner = Future<void> Function(
  BibleVersionInfo info,
  void Function(double progress) onProgress,
);

/// Cancels the download registered under [code].
typedef BibleDownloadCanceller = void Function(String code);

final bibleDownloadRunnerProvider = Provider<BibleDownloadRunner>((ref) {
  final dbService = ref.read(bibleDatabaseServiceProvider);
  final repo = ref.read(bibleVersionStateRepositoryProvider);
  return (info, onProgress) =>
      downloadBibleVersion(dbService, repo, info, onProgress: onProgress);
});

final bibleDownloadCancellerProvider = Provider<BibleDownloadCanceller>((ref) {
  final dbService = ref.read(bibleDatabaseServiceProvider);
  return dbService.cancelDownload;
});

/// App-scoped owner of Bible version downloads.
///
/// Deliberately not auto-disposed: a download outlives the screen that started
/// it, and any screen (versions list, inline prompt, the shell's indicator)
/// reads the same per-code state. Starting a code that is already active is a
/// no-op, so a second tap cannot queue a duplicate.
final bibleDownloadManagerProvider =
    NotifierProvider<BibleDownloadManager, Map<String, BibleDownloadState>>(
  BibleDownloadManager.new,
);

class BibleDownloadManager extends Notifier<Map<String, BibleDownloadState>> {
  @override
  Map<String, BibleDownloadState> build() => const {};

  /// Starts downloading [info]. Ignored if that code is already queued,
  /// downloading or installing.
  Future<void> start(BibleVersionInfo info) async {
    if (state[info.code]?.isActive ?? false) return;
    _set(BibleDownloadState(
      code: info.code,
      name: info.name,
      status: BibleDownloadStatus.queued,
    ));

    // Read once, up front: the notifier outlives screens but not necessarily
    // the container in tests.
    final runner = ref.read(bibleDownloadRunnerProvider);
    try {
      await runner(info, (p) {
        final current = state[info.code];
        if (current == null || !current.isActive) return;
        _set(current.copyWith(
          status: p >= 1.0
              ? BibleDownloadStatus.installing
              : BibleDownloadStatus.downloading,
          progress: p,
        ));
      });
      _set(state[info.code]!.copyWith(
        status: BibleDownloadStatus.done,
        progress: 1,
      ));
    } on BibleDownloadCancelled {
      _remove(info.code);
    } catch (e) {
      final current = state[info.code];
      if (current == null) return; // Dismissed while running.
      _set(current.copyWith(status: BibleDownloadStatus.failed, error: e));
    }
  }

  /// Stops a queued or running download and clears its state.
  void cancel(String code) {
    final current = state[code];
    if (current == null || !current.isActive) return;
    ref.read(bibleDownloadCancellerProvider)(code);
  }

  /// Restarts a failed download.
  Future<void> retry(BibleVersionInfo info) {
    if (state[info.code]?.status != BibleDownloadStatus.failed) {
      return Future.value();
    }
    return start(info);
  }

  /// Drops a finished or failed entry (e.g. once the user has seen it).
  void dismiss(String code) {
    final current = state[code];
    if (current != null && !current.isActive) _remove(code);
  }

  void _set(BibleDownloadState s) => state = {...state, s.code: s};

  void _remove(String code) => state = {...state}..remove(code);
}
