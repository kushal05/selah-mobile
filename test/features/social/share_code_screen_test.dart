// A shared-prayer link must show a read-only preview to anyone who is not on
// the prayer, and only hand over to the real prayer screen (whose permission
// checks apply) when the prayer is already on this device.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:notify/core/domain/enums/prayer_enums.dart';
import 'package:notify/core/sync/models/prayer_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/sync/repositories/local_share_code_repository.dart';
import 'package:notify/core/sync/repositories/prayer_repository.dart';
import 'package:notify/core/sync/services/public_share_api_service.dart';
import 'package:notify/core/sync/services/shared_prayer_api_service.dart';
import 'package:notify/features/social/presentation/screens/share_code_screen.dart';
import 'package:notify/l10n/app_localizations.dart';

class _FakeShared extends Fake implements SharedPrayerApiService {
  _FakeShared(this.result, {this.throws = false});
  final String? result;
  final bool throws;
  @override
  Future<String?> lookupShareCode(String shareCode) async {
    if (throws) throw Exception('401');
    return result;
  }
}

class _FakePublic extends Fake implements PublicShareApiService {
  _FakePublic(this.preview);
  final PublicPrayerPreview? preview;
  @override
  Future<PublicPrayerPreview?> resolvePrayer(String shareCode) async => preview;
}

class _FakeCodes extends Fake implements LocalShareCodeRepository {
  _FakeCodes([this.known = const {}]);
  final Map<String, String> known;
  @override
  Future<String?> prayerIdFor(String code) async => known[code.toUpperCase()];
}

class _ThrowingPublic extends Fake implements PublicShareApiService {
  @override
  Future<PublicPrayerPreview?> resolvePrayer(String shareCode) async =>
      throw Exception('offline');
}

class _FakePrayers extends Fake implements PrayerRepository {
  _FakePrayers({required this.hasLocal});
  final bool hasLocal;
  @override
  Future<PrayerModel?> getPrayerById(String id) async => hasLocal
      ? PrayerModel(
          id: id,
          userId: 'someone',
          title: 'Local',
          content: 'x',
          frequency: PrayerFrequency.daily,
          status: PrayerStatus.active,
          category: 'personal',
          answeredAt: null,
          updatedAt: 1,
          version: 1,
          deleted: 0,
          createdAt: 1,
        )
      : null;
}

const _preview = PublicPrayerPreview(
  title: 'Healing for Ann',
  content: 'Lord, please heal.',
  category: 'family',
  status: 'active',
  answeredAt: null,
  createdAt: 1,
  sharedByName: 'Ben',
);

Widget _app({
  required SharedPrayerApiService shared,
  required PublicShareApiService public,
  required PrayerRepository prayers,
  LocalShareCodeRepository? codes,
}) {
  final router = GoRouter(
    initialLocation: '/social/share/ABCDEF123456',
    routes: [
      GoRoute(
        path: '/social/share/:shareCode',
        builder: (_, s) =>
            ShareCodeScreen(shareCode: s.pathParameters['shareCode']!),
      ),
      GoRoute(
        path: '/prayers/:id',
        builder: (_, s) => Text('DETAIL ${s.pathParameters['id']}'),
      ),
      GoRoute(path: '/', builder: (_, _) => const Text('HOME')),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPrayerApiServiceProvider.overrideWithValue(shared),
      publicShareApiServiceProvider.overrideWithValue(public),
      prayerRepositoryProvider.overrideWithValue(prayers),
      localShareCodeRepositoryProvider.overrideWithValue(codes ?? _FakeCodes()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  testWidgets('a stranger (not signed in) gets a read-only preview',
      (tester) async {
    await tester.pumpWidget(_app(
      shared: _FakeShared(null, throws: true), // lookup needs a session
      public: _FakePublic(_preview),
      prayers: _FakePrayers(hasLocal: false),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Healing for Ann'), findsOneWidget);
    expect(find.text('Lord, please heal.'), findsOneWidget);
    expect(find.textContaining('View only'), findsOneWidget);
    expect(find.textContaining('Shared by Ben'), findsOneWidget);
    expect(find.textContaining('DETAIL'), findsNothing);
    // Nothing to change the prayer with.
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('a signed-in user who is not on the prayer also gets the preview',
      (tester) async {
    await tester.pumpWidget(_app(
      shared: _FakeShared('p1'),
      public: _FakePublic(_preview),
      prayers: _FakePrayers(hasLocal: false), // not synced to this device
    ));
    await tester.pumpAndSettle();

    expect(find.text('Healing for Ann'), findsOneWidget);
    expect(find.textContaining('DETAIL'), findsNothing);
  });

  testWidgets('a prayer already on this device opens the prayer screen',
      (tester) async {
    await tester.pumpWidget(_app(
      shared: _FakeShared('p1'),
      public: _FakePublic(_preview),
      prayers: _FakePrayers(hasLocal: true),
    ));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL p1'), findsOneWidget);
    expect(find.text('Healing for Ann'), findsNothing);
  });

  testWidgets('a revoked link shows the unavailable dialog, not a preview',
      (tester) async {
    await tester.pumpWidget(_app(
      shared: _FakeShared(null),
      public: _FakePublic(null),
      prayers: _FakePrayers(hasLocal: false),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Healing for Ann'), findsNothing);
  });

  testWidgets('the author opens their own link with no network', (tester) async {
    await tester.pumpWidget(_app(
      shared: _FakeShared(null, throws: true), // offline: server lookup fails
      public: _ThrowingPublic(), // offline: public fetch would fail too
      prayers: _FakePrayers(hasLocal: true),
      codes: _FakeCodes({'ABCDEF123456': 'p1'}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL p1'), findsOneWidget);
    expect(find.text('Healing for Ann'), findsNothing);
  });

  testWidgets('a remembered code whose prayer is gone from the device is not trusted',
      (tester) async {
    await tester.pumpWidget(_app(
      shared: _FakeShared(null, throws: true),
      public: _FakePublic(_preview),
      prayers: _FakePrayers(hasLocal: false),
      codes: _FakeCodes({'ABCDEF123456': 'p1'}),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('DETAIL'), findsNothing);
    expect(find.text('Healing for Ann'), findsOneWidget);
  });

  testWidgets('a failed load says so in the app language and offers Retry',
      (tester) async {
    await tester.pumpWidget(_app(
      shared: _FakeShared(null, throws: true),
      public: _ThrowingPublic(),
      prayers: _FakePrayers(hasLocal: false),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open the shared prayer'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
