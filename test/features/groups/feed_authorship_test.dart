// Who may change a thing in a group, and where.
//
// The feed printed the raw user id under a shared prayer — "by 7f3c9a…" —
// because the feed payload carries ids and names live only on the member list.
//
// It also grew edit and delete buttons, which is the part that was wrong: the
// same announcement then had two places deciding who could change it. The feed
// is a record of what happened. An announcement is managed on the
// announcements tab, a shared prayer on the prayers tab, and each decides once.
//
// Authority splits by what the action means. Rewriting someone's words is not
// moderation, so editing belongs to the author alone. Taking down an
// inappropriate post is moderation, so a group admin can delete and remove.
// Pinning is the group's own curation and stays with whoever manages it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/domain/enums/group_enums.dart';
import 'package:notify/core/sync/models/group_feed_item.dart';
import 'package:notify/core/sync/models/group_member_model.dart';
import 'package:notify/core/sync/models/group_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/groups/presentation/screens/group_detail_screen.dart';

const _viewer = 'user-me';
const _other = 'user-someone-else';

GroupModel _group() => GroupModel(
      id: 'g1', name: 'Youth', description: 'Weekday mornings',
      groupType: GroupType.prayerGroup, joinCode: 'ABC123',
      createdByUserId: _viewer, userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

GroupMemberModel _member(String userId, String display) => GroupMemberModel(
      id: 'm-$userId', groupId: 'g1', memberUserId: userId,
      memberUsername: 'handle_$userId', memberDisplayName: display,
      role: GroupMemberRole.member, userId: _viewer,
      updatedAt: 0, version: 1, deleted: 0, createdAt: 0,
    );

GroupFeedItem _prayerBy(String userId) => GroupFeedItem(
      id: 'gp-$userId', type: GroupFeedItemType.prayer, groupId: 'g1',
      createdAt: 1700000000000, prayerId: 'p1', userId: userId,
    );

GroupFeedItem _announcementBy(String userId) => GroupFeedItem(
      id: 'a-$userId', type: GroupFeedItemType.announcement, groupId: 'g1',
      createdAt: 1700000000000, title: 'Retreat', content: 'Sign up by Friday.',
      pinned: false, authorUserId: userId, authorUsername: 'handle_$userId',
    );

Future<List<String>> _openFeed(
  WidgetTester tester, {
  required List<GroupFeedItem> feed,
  required List<GroupMemberModel> members,
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
      groupMembersProvider('g1').overrideWith((ref) async => members),
      groupPrayersProvider('g1').overrideWith((ref) async => const []),
      groupAnnouncementsProvider('g1').overrideWith((ref) async => const []),
      groupFeedProvider('g1').overrideWith((ref) async => feed),
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
  await tester.tap(find.widgetWithText(Tab, 'Feed'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }

  return find.byType(Text).evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>().toList();
}

void main() {
  testWidgets('a shared prayer is credited by name, never by id',
      (tester) async {
    final texts = await _openFeed(
      tester,
      feed: [_prayerBy(_other)],
      members: [_member(_other, 'Hannah Varghese')],
    );

    expect(texts, contains('by Hannah Varghese'));
    expect(texts.any((t) => t.contains(_other)), isFalse,
        reason: 'the raw user id must never reach the screen: $texts');
  });

  testWidgets('an unknown author gets no byline rather than an id',
      (tester) async {
    // The author has left the group, so no member row carries their name.
    final texts = await _openFeed(
      tester,
      feed: [_prayerBy(_other)],
      members: const [],
    );

    expect(texts.any((t) => t.contains(_other)), isFalse,
        reason: 'an id is not a name: $texts');
    expect(texts.any((t) => t.startsWith('by ')), isFalse,
        reason: 'with no name to show, the byline is omitted: $texts');
  });

  testWidgets('the feed offers no actions, not even on your own posts',
      (tester) async {
    await _openFeed(
      tester,
      feed: [_announcementBy(_viewer), _prayerBy(_viewer)],
      members: [_member(_viewer, 'Me')],
    );

    expect(find.byIcon(Icons.more_vert), findsNothing,
        reason: 'the feed is a record; each item is managed on its own tab');
  });
}
