import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../l10n/l10n.dart';
import '../selectable_chip.dart';
import 'tag_picker_dialog.dart';

/// How many chips, laid out left to right and wrapped the way [Wrap] wraps them,
/// fit in [maxLines] lines.
///
/// [widths] are the chips' widths in order. A chip starts a new line when it
/// does not fit beside the one before it; one wider than the line gets a line to
/// itself (its label ellipsises to fit, as in [SelectableChip]).
int chipsThatFit({
  required List<double> widths,
  required double maxWidth,
  required double spacing,
  required int maxLines,
}) {
  var line = 1;
  var x = 0.0;
  for (var i = 0; i < widths.length; i++) {
    final w = widths[i] > maxWidth ? maxWidth : widths[i];
    if (x != 0 && x + spacing + w > maxWidth) {
      line++;
      x = 0;
    }
    if (line > maxLines) return i;
    x = (x == 0) ? w : x + spacing + w;
  }
  return widths.length;
}

/// The width a [SelectableChip] with [label] takes: 12px of padding each side,
/// the 15px label, and (selected, with a delete cross) the cross and its gap.
double selectableChipWidth(
  BuildContext context,
  String label, {
  required bool withDeleteCross,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 15),
    ),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width + 24 + (withDeleteCross ? 4 + AppTheme.iconMD : 0);
}

/// A screen's tags as chips, A to Z, in at most [maxLines] lines. Tags that do
/// not fit are behind "Show more tags", which opens a dialog with every tag to
/// tick any number of (see [TagPickerDialog]).
///
/// Tapping a chip ticks or unticks it. The field only reports the new selection
/// through [onChanged]; the screen owns the state.
class TagPickerField extends StatelessWidget {
  final List<TagOption> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// Lets the dialog create tags; null leaves "Add tag" out of it.
  final Future<TagOption?> Function(String name)? onCreate;

  final Color accent;
  final int maxLines;

  /// Show a cross on ticked chips, for screens where tapping one removes it.
  final bool showDelete;

  const TagPickerField({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.onCreate,
    this.accent = AppTheme.brandBlue,
    this.maxLines = 4,
    this.showDelete = true,
  });

  Future<void> _openDialog(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final picked = await TagPickerDialog.show(
      context,
      options: options,
      selected: selected,
      onCreate: onCreate,
      accent: accent,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = sortedTagOptions(options);

    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = [
          for (final o in sorted)
            selectableChipWidth(
              context,
              o.label,
              withDeleteCross: showDelete && selected.contains(o.id),
            ),
        ];
        final shown = chipsThatFit(
          widths: widths,
          maxWidth: constraints.maxWidth,
          spacing: AppTheme.spacing8,
          maxLines: maxLines,
        );
        final hidden = sorted.skip(shown).toList();
        final hiddenSelected = hidden.where((o) => selected.contains(o.id)).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppTheme.spacing8,
              runSpacing: AppTheme.spacing8,
              children: [
                for (final o in sorted.take(shown))
                  SelectableChip(
                    label: o.label,
                    accent: accent,
                    isSelected: selected.contains(o.id),
                    showDelete: showDelete,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      final next = {...selected};
                      if (!next.remove(o.id)) next.add(o.id);
                      onChanged(next);
                    },
                  ),
              ],
            ),
            if (hidden.isNotEmpty)
              TextButton(
                onPressed: () => _openDialog(context),
                style: TextButton.styleFrom(
                    foregroundColor: context.accentInk(accent)),
                child: Text(hiddenSelected == 0
                    ? l10n(context).showMoreTags
                    : l10n(context).showMoreTagsSelected(hiddenSelected)),
              ),
          ],
        );
      },
    );
  }
}
