import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../features/notes/presentation/widgets/note_template_picker_sheet.dart';
import '../../../../features/prayers/presentation/widgets/quick_prayer_sheet.dart';
import '../../../../shared/widgets/buttons/quick_action_button.dart';
import '../../../../features/bible/presentation/providers/bible_providers.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_label.dart';

/// One quick action, described rather than built.
///
/// The row and the folder render the same seven actions, so they are defined
/// once as data. Building them as widgets in two places is how the two lists
/// would drift apart.
class QuickActionSpec {
  final IconData icon;
  final String label;
  final Color color;
  final void Function(BuildContext) onTap;

  const QuickActionSpec({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// Quick actions on the home dashboard.
///
/// Four of the app's seven destinations have a slot in the tab bar; Promises,
/// Songs and People live behind "More" and were reachable from the dashboard
/// not at all. Their actions are here now, which gives the three hidden
/// destinations a front door on the screen everyone opens first.
///
/// The row scrolls horizontally rather than fitting four fixed tiles, and
/// "See more" opens all of them at once.
class QuickActionsRow extends ConsumerWidget {
  const QuickActionsRow({super.key});

  /// Every quick action, in priority order.
  ///
  /// [lastBook]/[lastChapter] come from reading history so "Continue reading"
  /// can resume; when there is none the action opens the Bible tab instead,
  /// so the tile is never a dead end.
  static List<QuickActionSpec> specs(
    BuildContext context,
    WidgetRef ref, {
    String? lastBook,
    int? lastChapter,
    String? lastTranslation,
  }) {
    return [
      QuickActionSpec(
        icon: Icons.add_circle_outline_rounded,
        label: l10n(context).newPrayer,
        color: AppTheme.brandBlue,
        onTap: (context) => showQuickPrayerSheet(context),
      ),
      QuickActionSpec(
        icon: Icons.edit_note_rounded,
        label: l10n(context).newNote,
        color: AppTheme.brandPurple,
        onTap: (context) => showNoteTemplatePicker(context),
      ),
      QuickActionSpec(
        icon: Icons.menu_book_rounded,
        label: lastBook == null
            ? l10n(context).readBible
            : l10n(context).continueReading,
        color: AppTheme.emerald,
        onTap: (context) {
          if (lastBook == null) {
            context.go(Routes.bible);
            return;
          }
          final book = ref.read(bibleRepositoryProvider).getBookByName(lastBook);
          context.push(
            '${Routes.bible}/chapter'
            '?bookId=${book?.id ?? 1}'
            '&chapter=$lastChapter'
            '&translation=$lastTranslation',
          );
        },
      ),
      QuickActionSpec(
        icon: Icons.search_rounded,
        label: l10n(context).actionSearch,
        color: AppTheme.teal,
        onTap: (context) => context.push(Routes.search),
      ),
      // The three below are the destinations hidden behind "More".
      QuickActionSpec(
        icon: Icons.bookmark_add_outlined,
        label: l10n(context).newPromise,
        color: AppTheme.rosePink,
        onTap: (context) => context.push(Routes.promiseNew),
      ),
      QuickActionSpec(
        icon: Icons.library_music_outlined,
        label: l10n(context).viewSongs,
        color: AppTheme.orange,
        onTap: (context) => context.go(Routes.songs),
      ),
      QuickActionSpec(
        icon: Icons.person_add_alt_1_outlined,
        label: l10n(context).addPerson,
        color: AppTheme.teal,
        onTap: (context) => context.push(Routes.socialPersonNew),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(bibleReferenceHistoryStreamProvider);
    final last = history.valueOrNull?.firstOrNull;
    final actions = specs(
      context,
      ref,
      lastBook: last?.book,
      lastChapter: last?.chapter,
      lastTranslation: last?.translation,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "See more" sits in the header rather than after the last tile: at
        // the right edge of the actions either way, but visible without
        // scrolling to the end to discover it.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Flexible: on a 320pt screen at a raised text size the label and
            // "See more" together overran the row by 17px. The label yields.
            Flexible(child: SectionLabel(l10n(context).quickActions)),
            TextButton(
              onPressed: () => showQuickActionsFolder(context, actions),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n(context).seeMore,
                      style: AppTheme.caption
                          .copyWith(fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // A Row inside a horizontal scroll view, not a ListView in a SizedBox.
        //
        // A ListView must be told its cross-axis extent, and every way of
        // computing that is a guess about font metrics — the first attempt
        // came out 4.8px short and clipped the labels on device while every
        // test passed. A Row takes the height of its tallest child, so there
        // is nothing to get wrong at any text size.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: AppTheme.spacing12),
                QuickActionButton(
                  icon: actions[i].icon,
                  label: actions[i].label,
                  color: actions[i].color,
                  onTap: actions[i].onTap,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Opens every quick action at once, laid out like a home-screen folder.
Future<void> showQuickActionsFolder(
  BuildContext context,
  List<QuickActionSpec> actions,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    // Light barrier. 45% black dimmed the page to rgb(134,135,136) from
    // rgb(244,245,247), and because the panel is translucent it sat on top of
    // that murk — the glass rendered a muddy rgb(193,178,163) instead of
    // reading bright. The blur already separates the panel from the page, so
    // the scrim only has to hint that the rest is inactive.
    barrierColor: Colors.black.withValues(alpha: 0.06),
    // See the note on _QuickActionsFolder.opener.
    builder: (dialogContext) =>
        _QuickActionsFolder(actions: actions, opener: context),
  );
}

/// A launcher-style folder: a rounded translucent panel holding the actions in
/// a grid, over a dimmed background.
class _QuickActionsFolder extends StatelessWidget {
  final List<QuickActionSpec> actions;

  /// The context that opened the folder.
  ///
  /// Actions run against this rather than the dialog's own context. This is
  /// defensive, not a bug fix: `pop()` starts the route's exit animation and
  /// does not deactivate its elements synchronously, so the tile's own
  /// context is in fact still usable at that moment — two attempts to write a
  /// failing test for it both passed with the tile context in place. The
  /// opener simply cannot go stale, which makes the ordering irrelevant.
  final BuildContext opener;

  const _QuickActionsFolder({required this.actions, required this.opener});

  @override
  Widget build(BuildContext context) {
    // Four columns, so seven actions fill two rows the way a folder does.
    const columns = 4;
    final rows = (actions.length / columns).ceil();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      // Glass rather than a panel: the blur is what makes a translucent
      // surface read as frosted instead of merely faded, because the content
      // behind it is still visible but unreadable. Without the blur, a low
      // alpha just looks like a washed-out card.
      child: ClipRRect(
        borderRadius: AppTheme.borderRadius3XL,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 22),
            decoration: BoxDecoration(
              // Frosted, not tinted. In light mode the glass is white so it
              // brightens what shows through rather than greying it; the
              // theme surface at a low alpha let the blurred gradient behind
              // set the panel's colour, which is what made it look dim.
              color: Theme.of(context).brightness == Brightness.dark
                  ? context.raisedSurface.withValues(alpha: 0.74)
                  : Colors.white.withValues(alpha: 0.82),
              borderRadius: AppTheme.borderRadius3XL,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // Uppercased here rather than in the ARB: the caps are a
              // typographic choice, and baking them into the string would
              // force every translation to carry them too.
              l10n(context).allQuickActions.toUpperCase(),
              // primaryText, not mutedText: the panel is glass now, so this
              // label sits over whatever is behind it — a blurred gradient in
              // the common case. A deliberately low-contrast grey was legible
              // on a solid surface and is not on this one.
              style: AppTheme.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: context.primaryText,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 16),
            // Sized to its rows, not to a fraction of the screen, so the
            // panel ends just below the last one.
            ...List.generate(rows, (r) {
              final start = r * columns;
              final slice =
                  actions.skip(start).take(columns).toList(growable: false);
              return Padding(
                padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : 14),
                child: Row(
                  mainAxisAlignment: slice.length == columns
                      ? MainAxisAlignment.spaceBetween
                      : MainAxisAlignment.start,
                  children: [
                    for (final a in slice)
                      Padding(
                        padding: EdgeInsets.only(
                            right: slice.length == columns ? 0 : 12),
                        child: QuickActionButton(
                          icon: a.icon,
                          label: a.label,
                          color: a.color,
                          onTap: (tileContext) {
                            Navigator.of(tileContext).pop();
                            a.onTap(opener);
                          },
                        ),
                      ),
                  ],
                ),
              );
            }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
