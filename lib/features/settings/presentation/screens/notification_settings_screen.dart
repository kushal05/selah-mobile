import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/notification_preference.dart';
import '../providers/notification_prefs_provider.dart';
import '../utils/reminder_time_utils.dart';

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
      backgroundColor: AppTheme.scaffoldGray,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppTheme.scaffoldGray,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Failed to load preferences',
                  style: AppTheme.bodyBase.copyWith(color: AppTheme.gray600)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    ref.invalidate(notifPrefNotifierProvider),
                child: const Text('Retry'),
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
        _SectionLabel(title: 'SOCIAL'),
        _NotifGroup(tiles: [
          _ToggleTile(
            title: 'Friend Requests',
            subtitle: 'When someone sends you a friend request',
            pref: _pref(_catFriendRequest),
            onChanged: (v) =>
                notifier.setEnabled(_catFriendRequest, enabled: v),
          ),
          _ToggleTile(
            title: 'New Friends',
            subtitle: 'When someone accepts your request',
            pref: _pref(_catFriendship),
            onChanged: (v) =>
                notifier.setEnabled(_catFriendship, enabled: v),
          ),
          _ToggleTile(
            title: 'Group Invites',
            subtitle: 'When you are invited to a group',
            pref: _pref(_catGroupInvite),
            onChanged: (v) =>
                notifier.setEnabled(_catGroupInvite, enabled: v),
          ),
          _ToggleTile(
            title: 'Group Announcements',
            subtitle: 'New announcements in your groups',
            pref: _pref(_catGroupAnnouncement),
            onChanged: (v) =>
                notifier.setEnabled(_catGroupAnnouncement, enabled: v),
          ),
          _ToggleTile(
            title: 'Group Prayers',
            subtitle: 'New shared prayers in your groups',
            pref: _pref(_catGroupPrayer),
            onChanged: (v) =>
                notifier.setEnabled(_catGroupPrayer, enabled: v),
          ),
          _ToggleTile(
            title: 'Prayer Collaborators',
            subtitle: 'When someone shares a prayer with you',
            pref: _pref(_catPrayerCollaborator),
            onChanged: (v) =>
                notifier.setEnabled(_catPrayerCollaborator, enabled: v),
          ),
        ]),

        // ── PRAYER ────────────────────────────────────────────────────
        _SectionLabel(title: 'PRAYER'),
        _NotifGroup(tiles: [
          _ToggleTile(
            title: 'Prayer Reminders',
            subtitle: 'Reminders for prayers with a schedule',
            pref: _pref(_catPrayerReminder),
            onChanged: (v) =>
                notifier.setEnabled(_catPrayerReminder, enabled: v),
          ),
        ]),

        // ── DAILY HABITS ──────────────────────────────────────────────
        _SectionLabel(title: 'DAILY HABITS'),
        _NotifGroup(tiles: [
          _HabitTile(
            title: 'Meditation',
            pref: _pref(_catMeditation),
            onToggle: (v) =>
                notifier.setEnabled(_catMeditation, enabled: v),
            onTimeChanged: (t) =>
                notifier.setReminderTime(_catMeditation, t),
          ),
          _HabitTile(
            title: 'Bible Reading',
            pref: _pref(_catBibleReading),
            onToggle: (v) =>
                notifier.setEnabled(_catBibleReading, enabled: v),
            onTimeChanged: (t) =>
                notifier.setReminderTime(_catBibleReading, t),
          ),
        ]),

        // ── ACCOUNT ───────────────────────────────────────────────────
        _SectionLabel(title: 'ACCOUNT'),
        _NotifGroup(tiles: [
          _ToggleTile(
            title: 'Account Activity',
            subtitle: 'Sign-ins, password changes',
            pref: _pref(_catAccountActivity),
            onChanged: (v) =>
                notifier.setEnabled(_catAccountActivity, enabled: v),
          ),
          _ToggleTile(
            title: 'App Updates',
            subtitle: 'Important announcements and updates',
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

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.spacing20, AppTheme.spacing20,
          AppTheme.spacing20, AppTheme.spacing6),
      child: Text(
        title,
        style: AppTheme.tiny.copyWith(
          fontWeight: FontWeight.w600,
          color: AppTheme.unselectedColor,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

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
        color: Colors.white,
        borderRadius: AppTheme.borderRadius3XL,
        border: Border.all(color: AppTheme.dividerColor),
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
                  color: AppTheme.dividerColor,
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
              style: AppTheme.caption.copyWith(color: AppTheme.unselectedColor))
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
            GestureDetector(
              onTap: () => _pickTime(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.scaffoldGray,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Text(
                  reminderDisplayTime(pref.reminderTime),
                  style: AppTheme.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
