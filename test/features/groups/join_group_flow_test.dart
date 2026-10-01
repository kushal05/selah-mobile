// What the app does with each answer the server can give to a join.
//
// The end-to-end check against the QA backend proves the server's half: a
// code resolves, a second user joins, the membership appears. This is the
// other half — the three outcomes that come back and what the person holding
// the phone is told about each.
//
// `notFound` and `alreadyMember` are not errors and must not be reported as
// one; a successful join has to refresh the group list, or the group the user
// just joined is missing from their own screen until something else reloads it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/domain/enums/group_enums.dart';
import 'package:notify/core/sync/models/group_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/sync/services/group_join_service.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/groups/presentation/widgets/join_group_dialog.dart';

GroupModel _group(String name) => GroupModel(
      id: 'g1', name: name, description: '',
      groupType: GroupType.prayerGroup, joinCode: 'ABC123',
      createdByUserId: 'u-other', userId: 'u-me',
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

/// Answers with whatever the test asked for, and records the code it was given.
class _FakeJoin extends GroupJoinService {
  _FakeJoin({
    required super.config,
    required super.authService,
    required super.interceptor,
    required this.answer,
  });

  final GroupJoinResult Function() answer;
  final codes = <String>[];

  @override
  Future<GroupJoinResult> joinGroup(String joinCode) async {
    codes.add(joinCode);
    return answer();
  }
}

Future<_FakeJoin> _join(
  WidgetTester tester,
  String code,
  GroupJoinResult Function() answer,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    groupJoinServiceProvider.overrideWith((ref) => _FakeJoin(
          config: ref.watch(syncConfigProvider),
          authService: ref.watch(authServiceProvider),
          interceptor: ref.watch(apiInterceptorProvider),
          answer: answer,
        )),
  ]);
  addTearDown(container.dispose);
  final fake = container.read(groupJoinServiceProvider) as _FakeJoin;

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(builder: (context, ref, _) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showJoinGroupDialog(context, ref),
              child: const Text('open'),
            ),
          ),
        );
      }),
    ),
  ));

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, code);
  final ctx = tester.element(find.byType(Scaffold).first);
  await tester.tap(find.widgetWithText(TextButton, l10n(ctx).join).last);
  await tester.pumpAndSettle();

  return fake;
}

void main() {
  testWidgets('a good code joins and says which group', (tester) async {
    final fake = await _join(tester, 'ABC123',
        () => GroupJoinResult(group: _group('Youth')));

    expect(fake.codes, ['ABC123'], reason: 'the typed code reaches the server');
    expect(find.textContaining('Youth'), findsOneWidget,
        reason: 'the person is told which group they joined');
  });

  testWidgets('a bad code is reported as invalid, not as a failure',
      (tester) async {
    await _join(tester, 'NOPE00', GroupJoinResult.notFound);

    final ctx = tester.element(find.byType(Scaffold).first);
    expect(find.text(l10n(ctx).invalidGroupCode), findsOneWidget);
  });

  testWidgets('joining a group you are already in says so', (tester) async {
    await _join(tester, 'ABC123',
        () => GroupJoinResult(group: _group('Youth'), alreadyMember: true));

    final ctx = tester.element(find.byType(Scaffold).first);
    expect(find.text(l10n(ctx).youAreAlreadyAMemberOfThisGroup), findsOneWidget);
    expect(find.textContaining('Joined'), findsNothing,
        reason: 'it must not also claim a fresh join');
  });

  testWidgets('a thrown error is surfaced, not swallowed', (tester) async {
    await _join(tester, 'ABC123', () => throw Exception('no connection'));

    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'the person must learn the join did not happen');
  });
}
