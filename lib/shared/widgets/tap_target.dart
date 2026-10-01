import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Holds a small control to the [AppTheme.minTapTarget] floor without making it
/// look any bigger.
///
/// Three controls in the notes filter row were drawn below the floor — an 18pt
/// bare icon, a 30pt clear button, and the filter chips once they went dense.
/// Growing them to 44 would have been wrong; they are meant to be quiet. What
/// was wrong was that only the drawn part answered a touch.
///
/// ### Why padding, and why the painted size has to be passed in
///
/// The obvious wrapper — a 44pt box with the control centred in it — does not
/// work. A sized box hands the child *tight* constraints, and these controls
/// centre their own contents, which makes them expand to fill whatever they are
/// given: the control grows straight back to 44 and nothing has been gained.
/// Padding is the one wrapper that adds space without constraining the child at
/// all, but it has to be told how much to add, which means knowing what the
/// child draws at. Hence [paintedHeight] and [paintedWidth].
///
/// Pass only the axis that falls short. A control already wide enough leaves
/// [paintedWidth] null and gets no horizontal padding.
///
/// The tap handler lives here rather than on the child so that near misses in
/// the padding are caught. A child with its own InkWell keeps it: the InkWell
/// sits deeper in the tree, so it wins a tap on the control itself and still
/// splashes, and this picks up only what lands in the strip. Taps are excluded
/// from semantics so a screen reader finds one button, not two — the child is
/// expected to carry its own [Semantics].
class TapTarget extends StatelessWidget {
  /// What the child draws at vertically. Padding makes up the difference.
  final double paintedHeight;

  /// What the child draws at horizontally, when that also falls short.
  final double? paintedWidth;

  final VoidCallback onTap;
  final Widget child;

  const TapTarget({
    super.key,
    required this.paintedHeight,
    required this.onTap,
    required this.child,
    this.paintedWidth,
  });

  /// Half the shortfall on one axis, or zero where the child already clears the
  /// floor — never negative, so a control larger than the floor is untouched.
  static double padFor(double painted) =>
      painted >= AppTheme.minTapTarget ? 0 : (AppTheme.minTapTarget - painted) / 2;

  @override
  Widget build(BuildContext context) {
    final vertical = padFor(paintedHeight);
    final horizontal = paintedWidth == null ? 0.0 : padFor(paintedWidth!);

    if (vertical == 0 && horizontal == 0) return child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: vertical,
          horizontal: horizontal,
        ),
        child: child,
      ),
    );
  }
}
