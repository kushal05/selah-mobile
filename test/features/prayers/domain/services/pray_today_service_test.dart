import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/database/sync_database.dart';
import 'package:notify/core/domain/enums/prayer_enums.dart';
import 'package:notify/core/sync/models/prayer_model.dart';
import 'package:notify/core/sync/repositories/entity_access_repository.dart';
import 'package:notify/core/sync/repositories/prayer_repository.dart';
import 'package:notify/features/prayers/domain/services/pray_today_service.dart';

void main() {
  late SyncDatabase db;
  late PrayerRepository prayerRepo;
  late PrayTodayService service;

  setUp(() {
    db = SyncDatabase.forTesting(NativeDatabase.memory());
    final entityAccessRepo = EntityAccessRepository(db, 'test-device');
    prayerRepo = PrayerRepository(db, 'test-device', entityAccessRepo);
    service = PrayTodayService(prayerRepo);
  });

  tearDown(() async {
    await db.close();
  });

  // A Monday derived programmatically so the tests don't depend on the real
  // calendar for a given hard-coded date.
  DateTime mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  PrayerModel prayer({
    required PrayerFrequency frequency,
    required DateTime createdAt,
    PrayerStatus status = PrayerStatus.active,
  }) {
    final ms = createdAt.millisecondsSinceEpoch;
    return PrayerModel(
      id: 'p-${frequency.name}-$ms',
      userId: 'user-1',
      title: 'Test',
      content: '',
      frequency: frequency,
      status: status,
      updatedAt: ms,
      version: 1,
      deleted: 0,
      createdAt: ms,
    );
  }

  group('qualifiesForToday', () {
    final monday = mondayOf(DateTime(2026, 6, 10));
    final saturday = monday.add(const Duration(days: 5));

    test('daily always qualifies', () {
      final p = prayer(frequency: PrayerFrequency.daily, createdAt: monday);
      expect(service.qualifiesForToday(p, monday), isTrue);
      expect(service.qualifiesForToday(p, saturday), isTrue);
    });

    test('weekdays qualifies Mon–Fri but not weekends', () {
      final p = prayer(frequency: PrayerFrequency.weekdays, createdAt: monday);
      expect(service.qualifiesForToday(p, monday), isTrue);
      expect(
        service.qualifiesForToday(p, monday.add(const Duration(days: 4))),
        isTrue, // Friday
      );
      expect(service.qualifiesForToday(p, saturday), isFalse);
      expect(
        service.qualifiesForToday(p, monday.add(const Duration(days: 6))),
        isFalse, // Sunday
      );
    });

    test('weekly qualifies only on the creation weekday', () {
      final p = prayer(frequency: PrayerFrequency.weekly, createdAt: monday);
      expect(
        service.qualifiesForToday(p, monday.add(const Duration(days: 7))),
        isTrue, // next Monday
      );
      expect(
        service.qualifiesForToday(p, monday.add(const Duration(days: 1))),
        isFalse, // Tuesday
      );
    });

    test('monthly qualifies only on the creation day-of-month', () {
      final p = prayer(
        frequency: PrayerFrequency.monthly,
        createdAt: DateTime(2026, 3, 15),
      );
      expect(service.qualifiesForToday(p, DateTime(2026, 6, 15)), isTrue);
      expect(service.qualifiesForToday(p, DateTime(2026, 6, 16)), isFalse);
    });

    test('asNeeded qualifies only on the day it was created', () {
      final p = prayer(
        frequency: PrayerFrequency.asNeeded,
        createdAt: DateTime(2026, 6, 10, 9),
      );
      expect(service.qualifiesForToday(p, DateTime(2026, 6, 10, 20)), isTrue);
      expect(service.qualifiesForToday(p, DateTime(2026, 6, 11, 1)), isFalse);
    });
  });

  group('todaysPrayers', () {
    test('returns empty for an empty userId', () async {
      expect(await service.todaysPrayers(''), isEmpty);
    });

    test('includes active daily prayers and excludes non-active ones',
        () async {
      final daily = await prayerRepo.createPrayer(
        userId: 'user-1',
        title: 'Daily prayer',
        frequency: PrayerFrequency.daily,
      );
      final answered = await prayerRepo.createPrayer(
        userId: 'user-1',
        title: 'Answered prayer',
        frequency: PrayerFrequency.daily,
      );
      await prayerRepo.markAsAnswered(answered.id);

      final today = await service.todaysPrayers('user-1');
      final ids = today.map((p) => p.id).toList();

      expect(ids, contains(daily.id));
      expect(ids, isNot(contains(answered.id)));
    });
  });
}
