import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/sync/models/friendship_model.dart';
import '../../../../core/sync/models/person_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../shared/widgets/tab_title.dart';

/// One directory for everyone the app knows about.
///
/// The app kept three separate ideas of a person: People (someone you pray
/// for, with no account), Friends (another Selah user), and group members —
/// in three features, with three screens and a friends search duplicated at
/// two routes. Nothing on screen explained the difference, so the obvious
/// question — "I pray for Anitha, why can't I share this with her?" — could
/// only be answered from the data model.
///
/// The distinction is real and worth keeping: it decides who can receive a
/// share. It just should not be three destinations. Here it is one list and
/// one badge.
///
/// This merges the two sources at the presentation layer rather than merging
/// the tables. `Person` and `Friendship` are separate sync entities with a
/// server contract behind them; unifying the schema is a migration, and it
/// should not be smuggled in behind a UI change. A `Person.linkedUserId`
/// column is the eventual fix — this gives users the single mental model now.
class PeopleDirectoryScreen extends ConsumerStatefulWidget {
  const PeopleDirectoryScreen({super.key});

  @override
  ConsumerState<PeopleDirectoryScreen> createState() =>
      _PeopleDirectoryScreenState();
}

enum _PeopleFilter { all, onSelah }

/// A row in the directory: a person you pray for, a Selah user, or both.
class _Entry {
  final PersonModel? person;
  final FriendshipModel? friend;

  const _Entry({this.person, this.friend});

  bool get onSelah => friend != null;
  String get name => person?.name ?? friend!.friendDisplayName;
  String get sortKey => name.toLowerCase();

  String subtitle(BuildContext context) {
    final relation = person?.relation.trim() ?? '';
    if (relation.isNotEmpty) return relation;
    if (friend != null) return '@${friend!.friendUsername}';
    return l10n(context).person;
  }
}

class _PeopleDirectoryScreenState
    extends ConsumerState<PeopleDirectoryScreen> {
  _PeopleFilter _filter = _PeopleFilter.all;

  @override
  Widget build(BuildContext context) {
    final strings = l10n(context);
    final peopleAsync = ref.watch(peopleStreamProvider);
    final friendsAsync = ref.watch(friendsListProvider);
    final pending = ref.watch(pendingRequestCountProvider).valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: context.pageGround,
      appBar: AppBar(
        backgroundColor: context.pageGround,
        elevation: 0,
        // no-back: the People tab root. A branch root has nothing to pop to,
        // so a back button would be a dead control.
        automaticallyImplyLeading: false,
        title: TabTitle(strings.people),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: strings.myGroups,
            onPressed: () => context.push(Routes.socialGroups),
          ),
          IconButton(
            icon: const Icon(Icons.person_search_outlined),
            tooltip: strings.findFriends,
            onPressed: () => context.push(Routes.socialFriendsSearch),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        backgroundColor: AppTheme.teal,
        foregroundColor: AppTheme.onAccent(AppTheme.teal),
        tooltip: strings.addPerson,
        onPressed: () => context.push(Routes.socialPersonNew),
        child: const Icon(Icons.person_add_alt_1_rounded),
      ),
      body: peopleAsync.when(
        loading: () => const ListTileSkeletonList(count: 6),
        error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
        data: (people) {
          final entries = _merge(people, friendsAsync.valueOrNull ?? const []);
          final visible = _filter == _PeopleFilter.onSelah
              ? entries.where((e) => e.onSelah).toList()
              : entries;

          return Column(
            children: [
              if (pending > 0) _requestsBanner(context, pending),
              _filterBar(context, entries),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: Icons.people_outline_rounded,
                        title: _filter == _PeopleFilter.onSelah
                            ? strings.noOneFromYourListIsOnSelahYet
                            : strings.noPeopleAddedYet,
                        message: _filter == _PeopleFilter.onSelah
                            ? strings.inviteSomeoneToShareYourPrayers
                            : strings.addThePeopleYouPrayFor,
                            accent: AppTheme.teal,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _row(context, visible[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Someone can be both: a Person you pray for *and* a Selah user. Matching
  /// on name keeps them one row rather than two, which is the whole point.
  List<_Entry> _merge(
      List<PersonModel> people, List<FriendshipModel> friends) {
    final byName = <String, FriendshipModel>{
      for (final f in friends) f.friendDisplayName.trim().toLowerCase(): f,
    };
    final entries = <_Entry>[];
    final matched = <String>{};

    for (final p in people) {
      final key = p.name.trim().toLowerCase();
      final friend = byName[key];
      if (friend != null) matched.add(key);
      entries.add(_Entry(person: p, friend: friend));
    }
    for (final f in friends) {
      final key = f.friendDisplayName.trim().toLowerCase();
      if (matched.contains(key)) continue;
      entries.add(_Entry(friend: f));
    }
    entries.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return entries;
  }

  Widget _requestsBanner(BuildContext context, int count) {
    final accent =
        AppTheme.accentOnTintFor(AppTheme.teal, Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: accent.withValues(alpha: AppTheme.alphaLight),
        borderRadius: AppTheme.borderRadius2XL,
        child: InkWell(
          borderRadius: AppTheme.borderRadius2XL,
          onTap: () => context.push(Routes.socialFriendRequests),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.mark_email_unread_outlined, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n(context).nFriendRequestsWaiting(count),
                    style: TextStyle(
                        color: context.primaryText,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterBar(BuildContext context, List<_Entry> entries) {
    final onSelah = entries.where((e) => e.onSelah).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          for (final f in _PeopleFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f == _PeopleFilter.all
                    ? '${l10n(context).all}  ${entries.length}'
                    : '${l10n(context).onSelah}  $onSelah'),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
                // The theme's chip selection is the app-wide blue; this tab
                // is teal, and a blue chip beside teal avatars and a teal
                // button reads as a mistake rather than a highlight.
                selectedColor:
                    AppTheme.teal.withValues(alpha: AppTheme.alphaMedLight),
                side: BorderSide(
                  color: _filter == f
                      ? AppTheme.teal.withValues(alpha: 0.4)
                      : context.hairline,
                ),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      _filter == f ? FontWeight.w600 : FontWeight.w500,
                  color: _filter == f
                      ? AppTheme.inkOnTintFor(
                          AppTheme.teal, Theme.of(context).brightness)
                      : context.primaryText,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, _Entry entry) {
    final accent =
        AppTheme.accentOnTintFor(AppTheme.teal, Theme.of(context).brightness);
    return Material(
      color: context.cardSurface,
      borderRadius: AppTheme.borderRadius2XL,
      child: InkWell(
        borderRadius: AppTheme.borderRadius2XL,
        onTap: () => _open(context, entry),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: AppTheme.alphaLight),
                child: Text(
                  entry.name.isEmpty ? '?' : entry.name[0].toUpperCase(),
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.primaryText)),
                    Text(entry.subtitle(context),
                        style: TextStyle(
                            fontSize: 14, color: context.mutedText)),
                  ],
                ),
              ),
              // The badge is the answer to "why can I share with her and not
              // with him" — stated where the question is asked.
              if (entry.onSelah)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: AppTheme.alphaLight),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                  ),
                  child: Text(
                    l10n(context).onSelah,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, _Entry entry) {
    final person = entry.person;
    if (person != null) {
      context.push('${Routes.socialPeople}/${person.id}');
      return;
    }
    // A Selah user who is not yet someone you pray for. Offer the one action
    // that connects the two halves of the model.
    showModalBottomSheet<void>(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      backgroundColor: context.cardSurface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Two different relationships sat here as unlabelled peers: a
            // person you pray ABOUT, and a Selah user you share WITH. The
            // subtitles say which is which, because nothing else did.
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: Text(l10n(sheetContext).addAsSomeoneYouPrayFor),
              subtitle: Text(l10n(sheetContext).someoneYouPrayForExplainer),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(Routes.socialPersonNew);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text(l10n(sheetContext).manageFriends),
              subtitle: Text(l10n(sheetContext).friendsExplainer),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(Routes.socialFriends);
              },
            ),
          ],
        ),
      ),
    );
  }
}
