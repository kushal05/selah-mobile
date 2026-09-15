import 'package:flutter/material.dart';

/// The heading in a tab root's [AppBar].
///
/// Every tab wrote the same expression inline —
/// `titleLarge.copyWith(color: onSurface)` — except the people directory,
/// which wrote a plain `Text(...)`. That falls back to
/// `appBarTheme.titleTextStyle` at 18 against every sibling's 28, so People
/// rendered visibly smaller than Notes, Prayers, Promises and Songs. Nothing
/// caught it: it analyses, it renders, and it only looks wrong beside the
/// others.
///
/// One widget, so the next tab added cannot miss the style by writing the
/// obvious thing.
class TabTitle extends StatelessWidget {
  final String text;
  const TabTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleLarge?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
    );
  }
}
