// Each item is managed in one place, by whoever has the right to.
//
// Editing is rewriting someone's words, so it belongs to the author alone.
// Deleting or removing is moderation, so a group admin has it too — an
// inappropriate post needs taking down and its author may not oblige. Pinning
// is the group's own curation, so it stays with whoever manages the group.
//
// These drive the real tabs rather than the card in isolation, because the
// permission is decided at the call site and that is what kept getting it
// wrong: the announcements tab gated the whole menu on `canManage`, so an
// author who did not run the group could not touch their own post.

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
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/groups/presentation/screens/group_detail_screen.dart';

const _viewer = 'user-me';
const _other = 'user-someone-else';

GroupModel _group() => GroupModel(
      id: 'g1', name: 'Youth', description: 'Weekday mornings',
      groupType: GroupType.prayerGroup, joinCode: 'ABC123',
      createdByUserId: _other, userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

GroupMemberModel _member(String userId, GroupMemberRole role) =>
    GroupMemberModel(
      id: 'm-$userId', groupId: 'g1', memberUserId: userId,
      memberUsername: 'handle_$userId', memberDisplayName: 'Name $userId',
      role: role, userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

GroupAnnouncementModel _announcement(String authorId) =>
    GroupAnnouncementModel(
      id: 'a1', groupId: 'g1', title: 'Retreat',
      content: 'Sign up by Friday.', authorUserId: authorId,
      authorUsername: 'handle_$authorId', pinned: false, userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

GroupPrayerModel _sharedPrayer(String sharerId) => GroupPrayerModel(
      id: 'gp1', groupId: 'g1', prayerId: 'p1', addedByUserId: sharerId,
      addedByUsername: 'handle_$sharerId', userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

Future<void> _openTab(
  WidgetTester tester,
  String tab, {
  required GroupMemberRole viewerRole,
  List<GroupAnnouncementModel> announcements = const [],
  List<GroupPrayerModel> prayers = const [],
}) async {
  tester.view.physicalSize = const Size(840, 2000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWith((ref) => _viewer),
      groupByIdProvider('g1').overrideWith((ref) async => _group()),
      groupMembersProvider('g1')
          .overrideWith((ref) async => [_member(_viewer, viewerRole)]),
      groupPrayersProvider('g1').overrideWith((ref) async => prayers),
      groupAnnouncementsProvider('g1').overrideWith((ref) async => announcements),
      groupFeedProvider('g1').overrideWith((ref) async => const []),
      prayersStreamProvider.overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const GroupDetailScreen(groupId: 'g1'),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  // ensureVisible first: the tab bar scrolls, and Announcements sits off the
  // right edge at this width. A tap on an off-screen tab silently does
  // nothing and leaves the screen on Overview, where every assertion about a
  // menu quietly finds none.
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
}

Future<Set<String>> _openMenu(WidgetTester tester) async {
  if (find.byIcon(Icons.more_vert).evaluate().isEmpty) return {};
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await tester.pump(const Duration(milliseconds: 400));

  final ctx = tester.element(find.byType(GroupDetailScreen));
  final l = l10n(ctx);
  return {
    for (final entry in {
      'edit': l.edit,
      'delete': l.actionDelete,
      'pin': 'Pin',
      'remove': l.removePrayerFromGroup,
    }.entries)
      if (find.text(entry.value).evaluate().isNotEmpty) entry.key,
  };
}

void main() {
  group('an announcement', () {
    // Verified against the QA server: a plain member is refused (403) when
    // they try to post an announcement, so this viewer is not someone who
    // wrote one as a member — they are a demoted admin. That is the state the
    // rule exists for, and it is reachable: promoting and demoting both work.
    testWidgets('its author may edit and delete it, but not pin it',
        (tester) async {
      await _openTab(tester, 'Announcements',
          viewerRole: GroupMemberRole.member,
          announcements: [_announcement(_viewer)]);

      expect(await _openMenu(tester), {'edit', 'delete'});
    });

    testWidgets('an admin may delete and pin it, but not rewrite it',
        (tester) async {
      await _openTab(tester, 'Announcements',
          viewerRole: GroupMemberRole.admin,
          announcements: [_announcement(_other)]);

      expect(await _openMenu(tester), {'delete', 'pin'});
    });

    testWidgets('a plain member gets no menu on someone else\'s post',
        (tester) async {
      await _openTab(tester, 'Announcements',
          viewerRole: GroupMemberRole.member,
          announcements: [_announcement(_other)]);

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });
  });

  group('a shared prayer', () {
    testWidgets('whoever shared it may remove it', (tester) async {
      await _openTab(tester, 'Prayers',
          viewerRole: GroupMemberRole.member,
          prayers: [_sharedPrayer(_viewer)]);

      expect(await _openMenu(tester), {'remove'});
    });

    testWidgets('an admin may remove someone else\'s', (tester) async {
      await _openTab(tester, 'Prayers',
          viewerRole: GroupMemberRole.admin,
          prayers: [_sharedPrayer(_other)]);

      expect(await _openMenu(tester), {'remove'});
    });

    testWidgets('a plain member may not remove someone else\'s',
        (tester) async {
      await _openTab(tester, 'Prayers',
          viewerRole: GroupMemberRole.member,
          prayers: [_sharedPrayer(_other)]);

      expect(find.byIcon(Icons.more_vert), findsNothing);
    });
  });
}
