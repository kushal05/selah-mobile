// What happens to a merge when the two devices disagree about what time it is.
//
// Every timestamp a merge compares was stamped by the device that wrote it,
// from its own clock. Nothing in the suite varied those clocks before this
// file, so a device hours or years off went unnoticed — and it does not lose a
// field here and there, it wins or loses every field of every merge for as
// long as the clock stays wrong.

import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/sync/engine/field_level_merger.dart';
import 'package:notify/core/sync/engine/sync_clock.dart';
import 'package:notify/core/testing/test_clock.dart';

/// A fixed, readable "now": 2026-01-01T00:00:00Z.
const int _now = 1767225600000;
const int _oneYear = 365 * 24 * 60 * 60 * 1000;
const int _oneMinute = 60 * 1000;

/// Device IDs chosen so that on a timestamp tie the *local* side wins
/// (`compareTo` is greater), which is what makes the bound's effect visible:
/// once the skewed remote timestamp is pulled back to a tie, the tiebreaker
/// decides, and it decides against it.
const String _localDevice = 'device-b';
const String _remoteDevice = 'device-a';

FieldMergeResult _mergeTitle({
  required int localTime,
  required int remoteTime,
  int now = _now,
  String localDeviceId = _localDevice,
  String remoteDeviceId = _remoteDevice,
}) {
  return FieldLevelMerger().merge(
    localFields: const {'title': 'local'},
    localFieldTimestamps: {'title': localTime},
    localUpdatedAt: localTime,
    localVersion: 1,
    remoteFields: const {'title': 'remote'},
    remoteFieldTimestamps: {'title': remoteTime},
    remoteUpdatedAt: remoteTime,
    remoteVersion: 1,
    localDeviceId: localDeviceId,
    remoteDeviceId: remoteDeviceId,
    mergeableFieldNames: const ['title'],
    now: now,
  );
}

void main() {
  group('a remote device whose clock runs ahead', () {
    test('does not win on the strength of its clock alone', () {
      // The remote wrote at the same instant as the local device, but its clock
      // says a year from now. Unbounded, that timestamp beats anything a
      // correct clock can produce, for a year.
      final result = _mergeTitle(
        localTime: _now,
        remoteTime: _now + _oneYear,
      );

      expect(result.fieldResolutions['title'], 'local');
      expect(result.mergedFields['title'], 'local');
    });

    test('does not leave its skew behind in the merged row', () {
      final result = _mergeTitle(
        localTime: _now,
        remoteTime: _now + _oneYear,
      );

      // If the future timestamp were written back, the row itself would beat
      // every later edit — the bug would survive the fix that bounded it.
      expect(result.mergedFieldTimestamps['title'], _now);
      expect(result.mergedUpdatedAt, _now);
    });

    test('loses to an edit made after it arrived', () {
      // The skewed write is bounded to when it was seen, so a later local edit
      // is genuinely later and takes the field.
      final result = _mergeTitle(
        localTime: _now + 10 * _oneMinute,
        remoteTime: _now + _oneYear,
        now: _now + 10 * _oneMinute,
      );

      expect(result.fieldResolutions['title'], 'local');
    });
  });

  group('the bound leaves ordinary merges alone', () {
    test('a remote edit a minute old still wins', () {
      final result = _mergeTitle(
        localTime: _now - 5 * _oneMinute,
        remoteTime: _now - _oneMinute,
      );

      expect(result.fieldResolutions['title'], 'remote');
      expect(result.mergedFieldTimestamps['title'], _now - _oneMinute);
    });

    test('a clock a minute fast is treated as jitter, not skew', () {
      // Inside the threshold: taken at face value, so the remote wins as it
      // would have before this bound existed.
      final result = _mergeTitle(
        localTime: _now,
        remoteTime: _now + _oneMinute,
      );

      expect(result.fieldResolutions['title'], 'remote');
      expect(result.mergedFieldTimestamps['title'], _now + _oneMinute);
    });

    test('a clock just past the threshold is bounded', () {
      final result = _mergeTitle(
        localTime: _now,
        remoteTime: _now + FieldLevelMerger.maxSkewMs + 1,
      );

      expect(result.mergedFieldTimestamps['title'], _now);
      expect(result.fieldResolutions['title'], 'local');
    });
  });

  test('the bound applies to the local device too', () {
    // Symmetry matters: if only remote timestamps were bounded, the device with
    // the wrong clock would still win every merge it performed itself, and the
    // two devices would settle on different values.
    final result = _mergeTitle(
      localTime: _now + _oneYear,
      remoteTime: _now,
      // Tiebreaker reversed, so a tie resolves to remote and the assertion
      // cannot pass by accident on the device-ID rule alone.
      localDeviceId: 'device-a',
      remoteDeviceId: 'device-b',
    );

    expect(result.fieldResolutions['title'], 'remote');
    expect(result.mergedUpdatedAt, _now);
  });

  test('two devices sharing an ID cannot be tie-broken, and both keep local',
      () {
    // Stated because the bound makes exact ties reachable: every timestamp too
    // far ahead collapses to the same observedAt, and a tie is settled by
    // comparing device IDs. Equal IDs compare to 0, which is not > 0, so both
    // sides prefer their own value and the two devices never converge.
    //
    // In practice the IDs differ — deviceIdProvider is replaced with a real one
    // during sync init, before any merge runs. The precondition is worth
    // knowing about anyway: if a merge ever runs while both sides still hold
    // the placeholder 'default-device-id', this is what it does.
    final result = _mergeTitle(
      localTime: _now,
      remoteTime: _now,
      localDeviceId: 'default-device-id',
      remoteDeviceId: 'default-device-id',
    );

    expect(result.fieldResolutions['title'], 'local');
  });

  test('a clock running behind still loses, which the bound cannot fix', () {
    // Stated as a test because it is a limit, not an oversight: a past-dated
    // timestamp is indistinguishable from a stale write. Only server-assigned
    // resolution would rescue this device's edits.
    final result = _mergeTitle(
      localTime: _now,
      remoteTime: _now - _oneYear,
    );

    expect(result.fieldResolutions['title'], 'local');
  });

  group('SyncClock', () {
    setUp(TestClock.reset);
    tearDown(() {
      SyncClock.reset();
      TestClock.reset();
    });

    test('reads the device clock until a server has been heard from', () {
      SyncClock.reset();
      TestClock.setFixed(_now);

      expect(SyncClock.offsetMs, isNull);
      expect(SyncClock.now(), _now);
    });

    test('corrects towards the server once it has', () {
      TestClock.setFixed(_now + _oneYear); // this device is a year fast
      SyncClock.observeServerTime(_now);

      expect(SyncClock.offsetMs, -_oneYear);
      expect(SyncClock.now(), _now);

      // And it keeps tracking: the correction is an offset, not a snapshot.
      TestClock.advance(_oneMinute);
      expect(SyncClock.now(), _now + _oneMinute);
    });

    test('does not move the device clock the rest of the app reads', () {
      TestClock.setFixed(_now + _oneYear);
      SyncClock.observeServerTime(_now);

      // Note dates, habit streaks and reminders all still see the device's own
      // clock; only merge decisions see the corrected one.
      expect(TestClock.now(), _now + _oneYear);
    });
  });
}
