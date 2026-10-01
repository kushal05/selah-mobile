// Leaving a group, and what is left behind.
//
// Leaving used to be one button and one outcome: the membership was deleted and
// the group vanished. People leave groups they still want to look back at, so
// leaving now asks what to do with it. Keeping it holds the group in the list
// as something readable and never writable; not keeping it is the old
// behaviour. Neither touches the group for anybody else.
//
// The successor question is separate and only arises when the person leaving is
// the last admin and more than one active member remains — with one there is
// nothing to choose, and with none there is nobody to ask about.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/domain/enums/group_enums.dart';
import 'package:notify/core/sync/models/group_member_model.dart';
import 'package:notify/core/sync/models/group_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/sync/services/groups_api_service.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/groups/presentation/screens/group_detail_screen.dart';

const _viewer = 'user-me';

/// Records how the app asked to leave.
class _RecordingGroupsApi extends GroupsApiService {
  _RecordingGroupsApi({
    required super.config,
    required super.authService,
    required super.interceptor,
  });

  final calls = <String>[];

  @override
  Future<void> leaveGroup(
    String groupId, {
    bool keepReadOnly = true,
    String? successorMemberId,
  }) async {
    calls.add('leave:keep=$keepReadOnly:successor=${successorMemberId ?? '-'}');
  }
}

GroupModel _group({int? viewerLeftAt}) => GroupModel(
      id: 'g1', name: 'Youth', description: 'Weekday mornings',
      groupType: GroupType.prayerGroup, joinCode: 'ABC123',
      createdByUserId: _viewer, userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
      viewerLeftAt: viewerLeftAt,
    );

GroupMemberModel _member(String userId, GroupMemberRole role) =>
    GroupMemberModel(
      id: 'm-$userId', groupId: 'g1', memberUserId: userId,
      memberUsername: 'handle_$userId', memberDisplayName: 'Name $userId',
      role: role, userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

Future<_RecordingGroupsApi> _openInfoTab(
  WidgetTester tester, {
  required List<GroupMemberModel> members,
  int? viewerLeftAt,
}) async {
  tester.view.physicalSize = const Size(840, 2000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    currentUserIdProvider.overrideWith((ref) => _viewer),
    groupsApiServiceProvider.overrideWith((ref) => _RecordingGroupsApi(
          config: ref.watch(syncConfigProvider),
          authService: ref.watch(authServiceProvider),
          interceptor: ref.watch(apiInterceptorProvider),
        )),
    groupByIdProvider('g1')
        .overrideWith((ref) async => _group(viewerLeftAt: viewerLeftAt)),
    groupMembersProvider('g1').overrideWith((ref) async => members),
    groupPrayersProvider('g1').overrideWith((ref) async => const []),
    groupAnnouncementsProvider('g1').overrideWith((ref) async => const []),
    groupFeedProvider('g1').overrideWith((ref) async => const []),
    prayersStreamProvider.overrideWith((ref) => Stream.value(const [])),
  ]);
  addTearDown(container.dispose);
  final api = container.read(groupsApiServiceProvider) as _RecordingGroupsApi;

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
  await tester.ensureVisible(find.widgetWithText(Tab, 'Info'));
  await tester.pump();
  await tester.tap(find.widgetWithText(Tab, 'Info'));
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

void main() {
  testWidgets('leaving keeps the group by default', (tester) async {
    final api = await _openInfoTab(tester, members: [
      _member(_viewer, GroupMemberRole.member),
      _member('u-other', GroupMemberRole.admin),
    ]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await tester.tap(find.text(l10n(ctx).leaveGroup).last);
    await tester.pumpAndSettle();
    // The checkbox is already ticked; confirm straight away.
    await tester.tap(find.text(l10n(ctx).leave).last);
    await tester.pumpAndSettle();

    expect(api.calls, ['leave:keep=true:successor=-']);
  });

  testWidgets('unticking keep drops the group instead', (tester) async {
    final api = await _openInfoTab(tester, members: [
      _member(_viewer, GroupMemberRole.member),
      _member('u-other', GroupMemberRole.admin),
    ]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await tester.tap(find.text(l10n(ctx).leaveGroup).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n(ctx).keepThisGroupToReadIt));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n(ctx).leave).last);
    await tester.pumpAndSettle();

    expect(api.calls, ['leave:keep=false:successor=-']);
  });

  testWidgets('the last admin with several others must name a successor',
      (tester) async {
    final api = await _openInfoTab(tester, members: [
      _member(_viewer, GroupMemberRole.admin),
      _member('u-b', GroupMemberRole.member),
      _member('u-c', GroupMemberRole.member),
    ]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await tester.tap(find.text(l10n(ctx).leaveGroup).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n(ctx).chooseTheNextAdmin), findsOneWidget,
        reason: 'the successor is asked for before anything else');
    expect(api.calls, isEmpty, reason: 'and nothing has been sent yet');

    // .last: the name is also on the screen behind the dialog.
    await tester.tap(find.text('Name u-c').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n(ctx).setAsAdmin));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n(ctx).leave).last);
    await tester.pumpAndSettle();

    expect(api.calls, ['leave:keep=true:successor=m-u-c']);
  });

  testWidgets('backing out of the successor choice cancels the leave',
      (tester) async {
    final api = await _openInfoTab(tester, members: [
      _member(_viewer, GroupMemberRole.admin),
      _member('u-b', GroupMemberRole.member),
      _member('u-c', GroupMemberRole.member),
    ]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await tester.tap(find.text(l10n(ctx).leaveGroup).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n(ctx).actionCancel));
    await tester.pumpAndSettle();

    expect(api.calls, isEmpty);
    expect(find.text(l10n(ctx).leave), findsNothing,
        reason: 'it must not fall through to the keep-or-drop question');
  });

  testWidgets('the last admin with one other is not asked anything',
      (tester) async {
    final api = await _openInfoTab(tester, members: [
      _member(_viewer, GroupMemberRole.admin),
      _member('u-b', GroupMemberRole.member),
    ]);
    final ctx = tester.element(find.byType(GroupDetailScreen));

    await tester.tap(find.text(l10n(ctx).leaveGroup).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n(ctx).chooseTheNextAdmin), findsNothing,
        reason: 'there is nothing to choose between');
    await tester.tap(find.text(l10n(ctx).leave).last);
    await tester.pumpAndSettle();

    expect(api.calls, ['leave:keep=true:successor=-']);
  });

  group('a group the viewer has left', () {
    testWidgets('says so, and offers removal rather than leaving',
        (tester) async {
      await _openInfoTab(tester,
          members: [_member('u-other', GroupMemberRole.admin)],
          viewerLeftAt: 1700000000000);
      final ctx = tester.element(find.byType(GroupDetailScreen));

      expect(find.text(l10n(ctx).readOnlyYouLeftThisGroup), findsOneWidget);
      expect(find.text(l10n(ctx).removeFromMyList), findsWidgets);
      expect(find.text(l10n(ctx).leaveGroup), findsNothing,
          reason: 'you cannot leave something you have already left');
    });

    testWidgets('removing it tells the server not to keep it', (tester) async {
      final api = await _openInfoTab(tester,
          members: [_member('u-other', GroupMemberRole.admin)],
          viewerLeftAt: 1700000000000);
      final ctx = tester.element(find.byType(GroupDetailScreen));

      await tester.tap(find.text(l10n(ctx).removeFromMyList).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n(ctx).remove).last);
      await tester.pumpAndSettle();

      expect(api.calls, ['leave:keep=false:successor=-']);
    });
  });
}
