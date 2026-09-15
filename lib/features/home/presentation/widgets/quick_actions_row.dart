import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/notes/presentation/widgets/note_template_picker_sheet.dart';
import '../../../../features/prayers/presentation/widgets/quick_prayer_sheet.dart';
import '../../../../shared/widgets/buttons/quick_action_button.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../features/bible/presentation/providers/bible_providers.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_label.dart';

/// Displays quick action buttons on the home dashboard.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label
        SectionLabel('Quick Actions'),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            QuickActionButton(
              icon: Icons.add_circle_outline_rounded,
              label: l10n(context).newPrayer,
              color: AppTheme.brandBlue,
              // The app's most-created object had no one-tap entry anywhere,
              // while Promise — a rarer action with a better contextual home
              // in the Bible reader's verse menu — held a slot.
              onTap: (context) => showQuickPrayerSheet(context),
            ),
            QuickActionButton(
              icon: Icons.edit_note_rounded,
              label: l10n(context).newNote,
              color: AppTheme.brandPurple,
              // Quick capture: open the template picker straight from the
              // home dashboard so users don't need to navigate to the notes
              // tab first. Tap-to-create-blank is still one tap inside the
              // sheet ("Blank Note" is the first option).
              onTap: (context) => showNoteTemplatePicker(context),
            ),
            const _ContinueReadingAction(),
            QuickActionButton(
              icon: Icons.search_rounded,
              label: l10n(context).actionSearch,
              color: AppTheme.teal,
              onTap: (context) => context.push(Routes.search),
            ),
          ],
        ),
      ],
    );
  }
}


/// Resumes the last chapter the user was reading.
///
/// Reading is the one daily action with no short path: the Bible tab asks for
/// a book and then a chapter every time, even when you are part-way through
/// one. The history the app already records is enough to skip both steps.
///
/// Falls back to opening the Bible tab when there is no history yet — a first
/// run, or after the user clears it — so the tile is never a dead end.
class _ContinueReadingAction extends ConsumerWidget {
  const _ContinueReadingAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(bibleReferenceHistoryStreamProvider);
    final last = history.valueOrNull?.firstOrNull;

    return QuickActionButton(
      icon: Icons.menu_book_rounded,
      label: last == null
          ? l10n(context).readBible
          : l10n(context).continueReading,
      color: AppTheme.emerald,
      onTap: (context) {
        if (last == null) {
          context.go(Routes.bible);
          return;
        }
        final book = ref.read(bibleRepositoryProvider).getBookByName(last.book);
        context.push(
          '${Routes.bible}/chapter'
          '?bookId=${book?.id ?? 1}'
          '&chapter=${last.chapter}'
          '&translation=${last.translation}',
        );
      },
    );
  }
}
