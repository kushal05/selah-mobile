import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/notification_preference.dart';
import '../providers/notification_prefs_provider.dart';
import '../utils/reminder_time_utils.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_label.dart';

// ── Category name constants ────────────────────────────────────────────────────

const _catFriendRequest = 'social_friend_request';
const _catFriendship = 'social_friendship';
const _catGroupInvite = 'social_group_invite';
const _catGroupAnnouncement = 'social_group_announcement';
const _catGroupPrayer = 'social_group_prayer';
const _catPrayerCollaborator = 'prayer_collaborator';
const _catPrayerReminder = 'habit_prayer_reminder';
const _catMeditation = habitCategoryMeditation;
const _catBibleReading = habitCategoryBibleReading;
const _catAccountActivity = 'account_activity';
const _catAccountUpdates = 'account_updates';

/// Notification preferences screen.
///
/// Shows toggles (and time-pickers for habit categories) that map 1-to-1 with
/// `NotificationPreference` objects returned by `GET /v1/notifications/preferences`.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notifPrefNotifierProvider);

    return Scaffold(
      backgroundColor: context.pageGround,
      appBar: AppBar(
        title: Text(l10n(context).notifications),
        backgroundColor: context.pageGround,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n(context).failedToLoadPreferences,
                  style: AppTheme.bodyBase.copyWith(color: context.subtleFill)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    ref.invalidate(notifPrefNotifierProvider),
                child: Text(l10n(context).retry),
              ),
            ],
          ),
        ),
        data: (prefs) => _Body(prefs: prefs),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _Body extends ConsumerWidget {
  final List<NotificationPreference> prefs;
  const _Body({required this.prefs});

  NotificationPreference _pref(String category) {
    return prefs.firstWhere(
      (p) => p.category == category,
      orElse: () =>
          NotificationPreference(category: category, enabled: true),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(notifPrefNotifierProvider.notifier);

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // ── SOCIAL ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.spacing16,
              AppTheme.spacing20, AppTheme.spacing16, AppTheme.spacing8),
          child: SectionLabel('SOCIAL'),
        ),
        _NotifGroup(tiles: [
          _ToggleTile(
            title: l10n(context).friendRequests,
            subtitle: l10n(context).whenSomeoneSendsYouAFriendRequest,
            pref: _pref(_catFriendRequest),
            onChanged: (v) =>
                notifier.setEnabled(_catFriendRequest, enabled: v),
          ),
          _ToggleTile(
            title: l10n(context).newFriends,
            subtitle: l10n(context).whenSomeoneAcceptsYourRequest,
            pref: _pref(_catFriendship),
            onChanged: (v) =>
                notifier.setEnabled(_catFriendship, enabled: v),
          ),
          _ToggleTile(
            title: l10n(context).groupInvites,
            subtitle: l10n(context).whenYouAreInvitedToAGroup,
            pref: _pref(_catGroupInvite),
            onChanged: (v) =>
                notifier.setEnabled(_catGroupInvite, enabled: v),
          ),
          _ToggleTile(
            title: l10n(context).groupAnnouncements,
            subtitle: l10n(context).newAnnouncementsInYourGroups,
            pref: _pref(_catGroupAnnouncement),
            onChanged: (v) =>
                notifier.setEnabled(_catGroupAnnouncement, enabled: v),
          ),
          _ToggleTile(
            title: l10n(context).groupPrayers,
            subtitle: l10n(context).newSharedPrayersInYourGroups,
            pref: _pref(_catGroupPrayer),
            onChanged: (v) =>
                notifier.setEnabled(_catGroupPrayer, enabled: v),
          ),
          _ToggleTile(
            title: l10n(context).prayerCollaborators,
            subtitle: l10n(context).whenSomeoneSharesAPrayerWithYou,
            pref: _pref(_catPrayerCollaborator),
            onChanged: (v) =>
                notifier.setEnabled(_catPrayerCollaborator, enabled: v),
          ),
        ]),

        // ── PRAYER ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.spacing16,
              AppTheme.spacing20, AppTheme.spacing16, AppTheme.spacing8),
          child: SectionLabel('PRAYER'),
        ),
        _NotifGroup(tiles: [
          _ToggleTile(
            title: l10n(context).prayerReminders,
            subtitle: l10n(context).remindersForPrayersWithASchedule,
            pref: _pref(_catPrayerReminder),
            onChanged: (v) =>
                notifier.setEnabled(_catPrayerReminder, enabled: v),
          ),
        ]),

        // ── DAILY HABITS ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.spacing16,
              AppTheme.spacing20, AppTheme.spacing16, AppTheme.spacing8),
          child: SectionLabel('DAILY HABITS'),
        ),
        _NotifGroup(tiles: [
          _HabitTile(
            title: l10n(context).meditation,
            pref: _pref(_catMeditation),
            onToggle: (v) =>
                notifier.setEnabled(_catMeditation, enabled: v),
            onTimeChanged: (t) =>
                notifier.setReminderTime(_catMeditation, t),
          ),
          _HabitTile(
            title: l10n(context).bibleReading,
            pref: _pref(_catBibleReading),
            onToggle: (v) =>
                notifier.setEnabled(_catBibleReading, enabled: v),
            onTimeChanged: (t) =>
                notifier.setReminderTime(_catBibleReading, t),
          ),
        ]),

        // ── ACCOUNT ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.spacing16,
              AppTheme.spacing20, AppTheme.spacing16, AppTheme.spacing8),
          child: SectionLabel('ACCOUNT'),
        ),
        _NotifGroup(tiles: [
          _ToggleTile(
            title: l10n(context).accountActivity,
            subtitle: l10n(context).signInsPasswordChanges,
            pref: _pref(_catAccountActivity),
            onChanged: (v) =>
                notifier.setEnabled(_catAccountActivity, enabled: v),
          ),
          _ToggleTile(
            title: l10n(context).appUpdates,
            subtitle: l10n(context).importantAnnouncementsAndUpdates,
            pref: _pref(_catAccountUpdates),
            onChanged: (v) =>
                notifier.setEnabled(_catAccountUpdates, enabled: v),
          ),
        ]),
      ],
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────


// ── Notification group (card) ─────────────────────────────────────────────────

class _NotifGroup extends StatelessWidget {
  final List<Widget> tiles;
  const _NotifGroup({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16, vertical: AppTheme.spacing2),
      decoration: BoxDecoration(
        color: context.cardSurface,
        borderRadius: AppTheme.borderRadius3XL,
        border: Border.all(color: context.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppTheme.borderRadius3XL,
        child: Column(
          children: [
            for (int i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 16,
                  color: context.pageGround,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Simple toggle tile ────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final NotificationPreference pref;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    this.subtitle,
    required this.pref,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title, style: AppTheme.headingSmall.copyWith(fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: AppTheme.caption.copyWith(color: context.mutedText))
          : null,
      value: pref.enabled,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16, vertical: AppTheme.spacing2),
    );
  }
}

// ── Habit tile (toggle + time picker) ────────────────────────────────────────

class _HabitTile extends StatelessWidget {
  final String title;
  final NotificationPreference pref;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String?> onTimeChanged;

  const _HabitTile({
    required this.title,
    required this.pref,
    required this.onToggle,
    required this.onTimeChanged,
  });

  Future<void> _pickTime(BuildContext context) async {
    final current = reminderUtcToLocal(pref.reminderTime) ??
        const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked != null) {
      onTimeChanged(reminderLocalToUtc(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile(
              title: Text(title,
                  style: AppTheme.headingSmall
                      .copyWith(fontWeight: FontWeight.w500)),
              value: pref.enabled,
              onChanged: onToggle,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (pref.enabled)
            Semantics(
              button: true,
              child: GestureDetector(
              onTap: () => _pickTime(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.pageGround,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.hairline),
                ),
                child: Text(
                  reminderDisplayTime(pref.reminderTime),
                  style: AppTheme.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            ),
        ],
      ),
    );
  }
}
