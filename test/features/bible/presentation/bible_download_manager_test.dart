import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/bible/data/bible_database_service.dart';
import 'package:notify/features/bible/domain/models/bible_version_info.dart';
import 'package:notify/features/bible/presentation/providers/bible_download_manager.dart';

BibleVersionInfo _info(String code) => BibleVersionInfo(
      code: code,
      name: 'Version $code',
      downloadUrl: 'https://example.invalid/$code.db',
      approximateSizeMb: 8,
      sortOrder: 0,
      isDefault: false,
      isDownloaded: false,
    );

/// Fake runner: each call parks on a completer the test controls.
class _FakeRunner {
  final calls = <String>[];
  final completers = <String, Completer<void>>{};
  final progress = <String, void Function(double)>{};
  final cancelled = <String>[];

  Future<void> run(BibleVersionInfo info, void Function(double) onProgress) {
    calls.add(info.code);
    progress[info.code] = onProgress;
    return (completers[info.code] = Completer<void>()).future;
  }

  void cancel(String code) {
    cancelled.add(code);
    completers[code]?.completeError(const BibleDownloadCancelled());
  }
}

ProviderContainer _container(_FakeRunner fake) {
  final c = ProviderContainer(overrides: [
    bibleDownloadRunnerProvider.overrideWithValue(fake.run),
    bibleDownloadCancellerProvider.overrideWithValue(fake.cancel),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('start tracks progress, then installing, then done', () async {
    final fake = _FakeRunner();
    final c = _container(fake);
    final m = c.read(bibleDownloadManagerProvider.notifier);

    final f = m.start(_info('KJV'));
    expect(c.read(bibleDownloadManagerProvider)['KJV']!.status,
        BibleDownloadStatus.queued);

    fake.progress['KJV']!(0.4);
    var s = c.read(bibleDownloadManagerProvider)['KJV']!;
    expect(s.status, BibleDownloadStatus.downloading);
    expect(s.progress, 0.4);

    fake.progress['KJV']!(1.0);
    expect(c.read(bibleDownloadManagerProvider)['KJV']!.status,
        BibleDownloadStatus.installing);

    fake.completers['KJV']!.complete();
    await f;
    expect(c.read(bibleDownloadManagerProvider)['KJV']!.status,
        BibleDownloadStatus.done);
  });

  test('dedupes a second start of an active code', () async {
    final fake = _FakeRunner();
    final c = _container(fake);
    final m = c.read(bibleDownloadManagerProvider.notifier);

    final f = m.start(_info('KJV'));
    await m.start(_info('KJV'));
    expect(fake.calls, ['KJV']);

    // A different code is independent.
    final g = m.start(_info('NIV'));
    expect(fake.calls, ['KJV', 'NIV']);

    fake.completers['KJV']!.complete();
    fake.completers['NIV']!.complete();
    await Future.wait([f, g]);
  });

  test('cancel stops the download and clears its state', () async {
    final fake = _FakeRunner();
    final c = _container(fake);
    final m = c.read(bibleDownloadManagerProvider.notifier);

    final f = m.start(_info('KJV'));
    m.cancel('KJV');
    await f;

    expect(fake.cancelled, ['KJV']);
    expect(c.read(bibleDownloadManagerProvider).containsKey('KJV'), isFalse);

    // And it can be started again.
    final g = m.start(_info('KJV'));
    expect(fake.calls, ['KJV', 'KJV']);
    fake.completers['KJV']!.complete();
    await g;
  });

  test('failure is recorded and retry runs it again', () async {
    final fake = _FakeRunner();
    final c = _container(fake);
    final m = c.read(bibleDownloadManagerProvider.notifier);

    final f = m.start(_info('KJV'));
    fake.completers['KJV']!.completeError(StateError('HTTP 500'));
    await f;
    var s = c.read(bibleDownloadManagerProvider)['KJV']!;
    expect(s.status, BibleDownloadStatus.failed);
    expect(s.error, isA<StateError>());

    final r = m.retry(_info('KJV'));
    expect(c.read(bibleDownloadManagerProvider)['KJV']!.status,
        BibleDownloadStatus.queued);
    fake.completers['KJV']!.complete();
    await r;
    expect(c.read(bibleDownloadManagerProvider)['KJV']!.status,
        BibleDownloadStatus.done);
    expect(fake.calls, ['KJV', 'KJV']);
  });

  test('retry is a no-op unless the download failed', () async {
    final fake = _FakeRunner();
    final c = _container(fake);
    final m = c.read(bibleDownloadManagerProvider.notifier);
    await m.retry(_info('KJV'));
    expect(fake.calls, isEmpty);
  });

  test('state survives every listener going away', () async {
    final fake = _FakeRunner();
    final c = _container(fake);
    final m = c.read(bibleDownloadManagerProvider.notifier);

    // A screen listening, then disposed mid-download.
    final sub = c.listen(bibleDownloadManagerProvider, (_, _) {});
    final f = m.start(_info('KJV'));
    fake.progress['KJV']!(0.5);
    sub.close();
    await Future<void>.delayed(Duration.zero);

    // A new screen sees the in-flight download, not an empty map.
    final s = c.read(bibleDownloadManagerProvider)['KJV']!;
    expect(s.status, BibleDownloadStatus.downloading);
    expect(s.progress, 0.5);

    fake.completers['KJV']!.complete();
    await f;
    expect(c.read(bibleDownloadManagerProvider)['KJV']!.status,
        BibleDownloadStatus.done);
  });

  test('an update runs the update runner, not the plain download', () async {
    final plain = _FakeRunner();
    final update = _FakeRunner();
    final c = ProviderContainer(overrides: [
      bibleDownloadRunnerProvider.overrideWithValue(plain.run),
      bibleUpdateRunnerProvider.overrideWithValue(update.run),
      bibleDownloadCancellerProvider.overrideWithValue(plain.cancel),
    ]);
    addTearDown(c.dispose);
    final m = c.read(bibleDownloadManagerProvider.notifier);

    final f = m.start(_info('TLB'), update: true);
    update.completers['TLB']!.complete();
    await f;

    expect(update.calls, ['TLB']);
    expect(plain.calls, isEmpty);
    expect(c.read(bibleDownloadManagerProvider)['TLB']!.status,
        BibleDownloadStatus.done);
  });

  test('a download that is not an update uses the plain runner', () async {
    final plain = _FakeRunner();
    final update = _FakeRunner();
    final c = ProviderContainer(overrides: [
      bibleDownloadRunnerProvider.overrideWithValue(plain.run),
      bibleUpdateRunnerProvider.overrideWithValue(update.run),
      bibleDownloadCancellerProvider.overrideWithValue(plain.cancel),
    ]);
    addTearDown(c.dispose);

    final f = c.read(bibleDownloadManagerProvider.notifier).start(_info('NIV'));
    plain.completers['NIV']!.complete();
    await f;

    expect(plain.calls, ['NIV']);
    expect(update.calls, isEmpty);
  });
}
