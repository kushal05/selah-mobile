import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/notes/presentation/widgets/note_template_picker_sheet.dart';
import '../../../../shared/widgets/buttons/quick_action_button.dart';

/// Displays quick action buttons on the home dashboard.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = StatefulNavigationShell.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        _SectionLabel(title: 'Quick Actions'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            QuickActionButton(
              icon: Icons.add_circle_outline_rounded,
              label: 'New Note',
              color: AppTheme.brandPurple,
              // Quick capture: open the template picker straight from the
              // home dashboard so users don't need to navigate to the notes
              // tab first. Tap-to-create-blank is still one tap inside the
              // sheet ("Blank Note" is the first option).
              onTap: (context) => showNoteTemplatePicker(context),
            ),
            QuickActionButton(
              icon: Icons.wb_sunny_outlined,
              label: 'Pray Today',
              color: AppTheme.brandBlue,
              onTap: (context) => context.push(Routes.prayerToday),
            ),
            QuickActionButton(
              icon: Icons.bookmark_outline_rounded,
              label: 'Promise',
              color: AppTheme.rosePink,
              onTap: (context) => shell.goBranch(4),
            ),
            QuickActionButton(
              icon: Icons.search_rounded,
              label: 'Search',
              color: AppTheme.teal,
              onTap: (context) => context.push(Routes.search),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shared brand-accent section label used across the home dashboard.
class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppTheme.textDark,
              ),
        ),
      ],
    );
  }
}
