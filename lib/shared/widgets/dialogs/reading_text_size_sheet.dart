import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/reading_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../l10n/l10n.dart';

/// Bottom sheet for choosing the reader text size.
///
/// Shows a live preview of real scripture at the selected size, so the choice
/// is made by looking at the result rather than by reading a label. Both a
/// stepper and a labelled row are offered — the stepper is faster, the row
/// says where you are in the range.
Future<void> showReadingTextSizeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
    context: context,
    // The preview text grows with the selected size — at 'Largest' on a short
    // screen the content is taller than the default half-height sheet, which
    // overflowed the column. Scroll-controlled so the sheet can grow, and the
    // body scrolls once it runs out of room.
    isScrollControlled: true,
    backgroundColor: context.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ReadingTextSizeSheet(),
  );
}

class _ReadingTextSizeSheet extends ConsumerWidget {
  const _ReadingTextSizeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(readingTextSizeProvider);
    final notifier = ref.read(readingTextSizeProvider.notifier);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.subtleFill,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n(context).textSize,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n(context).changesHowBiblePassagesNotesAndLyricsAreShow,
              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),

            // Live preview at the selected size.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.subtleFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.subtleFill),
              ),
              child: Text(
                l10n(context).forGodSoLovedTheWorldThatHeGaveHisOnlyBegott,
                style: TextStyle(
                  fontSize: kReadingBaseFontSize * size.scale,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Stepper — large targets, clearly disabled at the ends.
            Row(
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  label: l10n(context).smallerText,
                  onPressed:
                      size.isSmallest ? null : () => notifier.decrease(),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      size.label,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  label: l10n(context).largerText,
                  onPressed: size.isLargest ? null : () => notifier.increase(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Direct selection, so the whole range is visible at once.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in ReadingTextSize.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: option == size,
                    onSelected: (_) => notifier.set(option),
                    labelStyle: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          option == size ? FontWeight.w600 : FontWeight.w500,
                      color: option == size
                          ? AppTheme.accentOnTintFor(
                              AppTheme.brandBlue, Theme.of(context).brightness)
                          : context.primaryText,
                    ),
                    backgroundColor: context.cardSurface,
                    selectedColor: AppTheme.brandBlue.withValues(alpha: 0.12),
                    side: BorderSide(
                      color: option == size
                          ? AppTheme.brandBlue
                          : AppTheme.inputBorderColor,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A 48x48 stepper button — the accessible minimum, not the icon's size.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _StepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: enabled
              ? context.subtleFill
              : context.subtleFill.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Icon(
              icon,
              size: 24,
              color: enabled ? context.primaryText : context.hintText,
            ),
          ),
        ),
      ),
    );
  }
}
