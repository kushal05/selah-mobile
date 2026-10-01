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
/// ### How it sizes itself
///
/// The target is at least 44 on each axis and the child sits centred in it at
/// whatever size the child draws. Nothing is passed in: the wrapper measures
/// the child by laying it out, so a control that is later redrawn smaller still
/// gets a full target.
///
/// That needs one thing of the child — that it **shrink-wraps**, drawing at its
/// own size when offered more. A control that centres its contents with
/// `Container(alignment: …)` does not: alignment centres by expanding, so it
/// would grow to fill the 44 and look bigger. FilterPill used to be built that
/// way; it now centres with `Center(widthFactor: 1, heightFactor: 1)`, which
/// shrink-wraps. Use that pattern in anything wrapped here.
///
/// ### The option this replaced
///
/// The first version took the child's drawn size as parameters and padded by
/// the difference. That worked for any child, including ones that expand, and
/// was chosen because FilterPill expanded at the time. Its cost was that the
/// numbers had to be kept in step with the drawing by hand, and a stale number
/// failed invisibly: redraw a control smaller, forget the constant, and the
/// target quietly fell under 44 with nothing on screen to show it. This version
/// fails the other way — a child that expands looks visibly too big — which is
/// the failure someone will notice. With every user now shrink-wrapping, the
/// parameters were guarding against nothing.
///
/// ### Taps and semantics
///
/// The tap handler lives here rather than on the child so that near misses in
/// the margin are caught. A child with its own InkWell keeps it: the InkWell
/// sits deeper in the tree, so it wins a tap on the control itself and still
/// splashes, and this picks up only what lands around it. Taps are excluded
/// from semantics so a screen reader finds one button, not two — the child is
/// expected to carry its own [Semantics].
class TapTarget extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const TapTarget({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    // a11y-exempt: widens the hit area of [child], which carries its own
    // Semantics; this node is deliberately excluded so a screen reader finds
    // one button here, not two.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppTheme.minTapTarget,
          minHeight: AppTheme.minTapTarget,
        ),
        // The factors keep the child at its own size inside the floor rather
        // than stretching it to fill — the one thing the doc above asks of it.
        child: Center(widthFactor: 1, heightFactor: 1, child: child),
      ),
    );
  }
}
