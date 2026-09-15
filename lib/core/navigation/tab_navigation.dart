import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Switches the bottom-tab branch, when the caller is inside the tab shell.
///
/// Six screens used to read `StatefulNavigationShell.of(context)` at the top
/// of `build`, purely to call `goBranch` from a tap handler further down.
/// That lookup throws outside the shell, so those screens — notes, prayers,
/// promises, songs, people and the overview grid, the busiest in the app —
/// could not be pumped in a test or reused anywhere else. The dependency was
/// on a capability needed at the moment of a tap, declared as a requirement
/// of rendering at all.
///
/// Looked up here at call time with [StatefulNavigationShell.maybeOf], so a
/// screen renders fine without a shell and the tap is simply a no-op.
void goToTab(BuildContext context, int branchIndex) {
  StatefulNavigationShell.maybeOf(context)?.goBranch(branchIndex);
}
