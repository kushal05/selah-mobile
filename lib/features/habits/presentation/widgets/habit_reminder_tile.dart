import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../features/settings/domain/models/notification_preference.dart';
import '../../../../features/settings/presentation/providers/notification_prefs_provider.dart';
import '../../../../features/settings/presentation/utils/reminder_time_utils.dart';

const _catMeditation = habitCategoryMeditation;
const _catBibleReading = habitCategoryBibleReading;

/// Inline reminder tile used on the Habits screen.
/// Mirrors the _HabitTile in notification_settings_screen.dart but is
/// styled to fit within the Habits screen card layout.
class HabitReminderSection extends ConsumerWidget {
  const HabitReminderSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefsAsync = ref.watch(notifPrefNotifierProvider);

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16, vertical: AppTheme.spacing6),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.spacing16, AppTheme.spacing14,
                AppTheme.spacing16, AppTheme.spacing8),
            child: Row(
              children: [
                Icon(Icons.notifications_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: AppTheme.spacing6),
                Text(
                  'Daily Reminders',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          prefsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppTheme.spacing16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(AppTheme.spacing16),
              child: Text('Could not load reminders',
                  style: AppTheme.caption
                      .copyWith(color: AppTheme.unselectedColor)),
            ),
            data: (prefs) {
              NotificationPreference? pref(String cat) {
                try {
                  return prefs.firstWhere((p) => p.category == cat);
                } catch (_) {
                  return null;
                }
              }

              final notifier = ref.read(notifPrefNotifierProvider.notifier);

              final tiles = [
                _ReminderTile(
                  label: 'Bible Reading',
                  pref: pref(_catBibleReading),
                  onToggle: (v) =>
                      notifier.setEnabled(_catBibleReading, enabled: v),
                  onTimeChanged: (t) =>
                      notifier.setReminderTime(_catBibleReading, t),
                ),
                _ReminderTile(
                  label: 'Meditation',
                  pref: pref(_catMeditation),
                  onToggle: (v) =>
                      notifier.setEnabled(_catMeditation, enabled: v),
                  onTimeChanged: (t) =>
                      notifier.setReminderTime(_catMeditation, t),
                ),
              ];

              return Column(
                children: [
                  for (int i = 0; i < tiles.length; i++) ...[
                    tiles[i],
                    if (i < tiles.length - 1)
                      Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 16,
                          color: AppTheme.dividerColor),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppTheme.spacing8),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final String label;
  final NotificationPreference? pref;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String?> onTimeChanged;

  const _ReminderTile({
    required this.label,
    required this.pref,
    required this.onToggle,
    required this.onTimeChanged,
  });

  Future<void> _pickTime(BuildContext context) async {
    final current =
        reminderUtcToLocal(pref?.reminderTime) ?? const TimeOfDay(hour: 8, minute: 0);
    final picked =
        await showTimePicker(context: context, initialTime: current);
    if (picked != null) {
      onTimeChanged(reminderLocalToUtc(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = pref?.enabled ?? true;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing16, vertical: AppTheme.spacing4),
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile(
              title: Text(label,
                  style: AppTheme.headingSmall
                      .copyWith(fontWeight: FontWeight.w500)),
              value: enabled,
              onChanged: onToggle,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          if (enabled)
            GestureDetector(
              onTap: () => _pickTime(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing10,
                    vertical: AppTheme.spacing6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: AppTheme.borderRadiusLG,
                ),
                child: Text(
                  reminderDisplayTime(pref?.reminderTime),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
