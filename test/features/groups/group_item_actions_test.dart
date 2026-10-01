// The menu items are wired to the actions they name.
//
// The permission tests assert what appears in each menu. That says nothing
// about what tapping it does, and the switch in AnnouncementCard maps three
// string values onto three callbacks — swap two and every permission test
// still passes while the app deletes a post you asked to edit.
//
// So these tap the item and watch which API call comes out, through a fake
// service that records instead of talking to the network.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/domain/enums/group_enums.dart';
import 'package:notify/core/sync/models/group_announcement_model.dart';
import 'package:notify/core/sync/models/group_member_model.dart';
import 'package:notify/core/sync/models/group_model.dart';
import 'package:notify/core/sync/models/group_prayer_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/sync/services/group_content_api_service.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/groups/presentation/screens/group_detail_screen.dart';

const _viewer = 'user-me';

/// Records what was asked of it; never reaches the network.
class _RecordingApi extends GroupContentApiService {
  _RecordingApi({
    required super.config,
    required super.authService,
    required super.interceptor,
  });

  final calls = <String>[];

  @override
  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
  }) async =>
      calls.add('deleteAnnouncement:$announcementId');

  @override
  Future<GroupAnnouncementModel> updateAnnouncement({
    required String groupId,
    required String announcementId,
    String? title,
    String? content,
    bool? pinned,
  }) async {
    calls.add('updateAnnouncement:$announcementId:pinned=$pinned');
    return _announcement();
  }

  @override
  Future<void> removeGroupPrayer({
    required String groupId,
    required String groupPrayerId,
  }) async =>
      calls.add('removeGroupPrayer:$groupPrayerId');
}

GroupModel _group() => GroupModel(
      id: 'g1', name: 'Youth', description: 'Weekday mornings',
      groupType: GroupType.prayerGroup, joinCode: 'ABC123',
      createdByUserId: _viewer, userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

GroupMemberModel _member(GroupMemberRole role) => GroupMemberModel(
      id: 'm1', groupId: 'g1', memberUserId: _viewer,
      memberUsername: 'me', memberDisplayName: 'Me', role: role,
      userId: _viewer, updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

GroupAnnouncementModel _announcement() => GroupAnnouncementModel(
      id: 'a1', groupId: 'g1', title: 'Retreat', content: 'Sign up by Friday.',
      authorUserId: _viewer, authorUsername: 'me', pinned: false,
      userId: _viewer, updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

GroupPrayerModel _sharedPrayer() => GroupPrayerModel(
      id: 'gp1', groupId: 'g1', prayerId: 'p1', addedByUserId: _viewer,
      addedByUsername: 'me', userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

Future<_RecordingApi> _openTab(
  WidgetTester tester,
  String tab, {
  GroupMemberRole role = GroupMemberRole.member,
  List<GroupAnnouncementModel> announcements = const [],
  List<GroupPrayerModel> prayers = const [],
}) async {
  tester.view.physicalSize = const Size(840, 2000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // An explicit container, because the override is lazy: nothing builds the
  // service until a mutation asks for it, and the test needs the instance
  // before that to watch what it is asked to do.
  final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWith((ref) => _viewer),
      groupContentApiServiceProvider.overrideWith((ref) {
        return _RecordingApi(
          config: ref.watch(syncConfigProvider),
          authService: ref.watch(authServiceProvider),
          interceptor: ref.watch(apiInterceptorProvider),
        );
      }),
      groupByIdProvider('g1').overrideWith((ref) async => _group()),
      groupMembersProvider('g1').overrideWith((ref) async => [_member(role)]),
      groupPrayersProvider('g1').overrideWith((ref) async => prayers),
      groupAnnouncementsProvider('g1').overrideWith((ref) async => announcements),
      groupFeedProvider('g1').overrideWith((ref) async => const []),
      prayersStreamProvider.overrideWith((ref) => Stream.value(const [])),
  ]);
  addTearDown(container.dispose);
  final api = container.read(groupContentApiServiceProvider) as _RecordingApi;

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const GroupDetailScreen(groupId: 'g1'),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.ensureVisible(find.widgetWithText(Tab, tab));
  await tester.pump();
  await tester.tap(find.widgetWithText(Tab, tab));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return api;
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.more_vert).first);
  // The popup route animates in behind an IgnorePointer; tapping an item
  // before it settles silently misses and the test reads as "nothing
  // happened". pumpAndSettle is safe here — no field is focused, so there is
  // no caret blinking forever.
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('Delete on an announcement deletes that announcement',
      (tester) async {
    final api = await _openTab(tester, 'Announcements',
        announcements: [_announcement()]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await _choose(tester, l10n(ctx).actionDelete);
    // The confirmation, which must be cleared before anything happens.
    expect(api.calls, isEmpty, reason: 'nothing until the dialog is confirmed');
    await tester.tap(find.text(l10n(ctx).actionDelete).last);
    await _settle(tester);

    expect(api.calls, ['deleteAnnouncement:a1']);
  });

  testWidgets('Cancelling the confirmation deletes nothing', (tester) async {
    final api = await _openTab(tester, 'Announcements',
        announcements: [_announcement()]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await _choose(tester, l10n(ctx).actionDelete);
    await tester.tap(find.text(l10n(ctx).actionCancel));
    await _settle(tester);

    expect(api.calls, isEmpty,
        reason: 'a destructive action must not fire on cancel');
  });

  testWidgets('Edit opens the editor rather than destroying anything',
      (tester) async {
    final api = await _openTab(tester, 'Announcements',
        announcements: [_announcement()]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await _choose(tester, l10n(ctx).edit);

    expect(find.text(l10n(ctx).editAnnouncement), findsOneWidget,
        reason: 'Edit must open the edit dialog');
    expect(api.calls, isEmpty, reason: 'and must not call anything yet');
  });

  testWidgets('closing the edit dialog does not use a freed controller',
      (tester) async {
    await _openTab(tester, 'Announcements', announcements: [_announcement()]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await _choose(tester, l10n(ctx).edit);
    // Asserted before dismissing: this test's only claim is that nothing
    // throws, and "nothing threw" is also true of a dialog that never opened.
    expect(find.text(l10n(ctx).editAnnouncement), findsOneWidget);

    // Dismiss it. The dialog's controllers are disposed the moment showDialog
    // returns, while the route is still animating out and the fields are
    // still being rebuilt.
    await tester.tap(find.text(l10n(ctx).actionCancel).last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the text fields outlive the await by one animation');
  });

  testWidgets('Pin pins, and does not delete', (tester) async {
    final api = await _openTab(tester, 'Announcements',
        role: GroupMemberRole.admin, announcements: [_announcement()]);

    await _choose(tester, 'Pin');
    await _settle(tester);

    expect(api.calls, ['updateAnnouncement:a1:pinned=true']);
  });

  testWidgets('Remove on a shared prayer removes that share', (tester) async {
    final api =
        await _openTab(tester, 'Prayers', prayers: [_sharedPrayer()]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await _choose(tester, l10n(ctx).removePrayerFromGroup);
    expect(api.calls, isEmpty, reason: 'nothing until the dialog is confirmed');
    await tester.tap(find.text(l10n(ctx).remove).last);
    await _settle(tester);

    expect(api.calls, ['removeGroupPrayer:gp1']);
  });
}
