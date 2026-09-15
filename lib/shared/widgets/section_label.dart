import 'package:flutter/material.dart';

import '../../core/theme/theme_colors.dart';

/// The small uppercase heading that separates one part of a screen from the
/// next.
///
/// Five screens had written their own — under three different field names
/// (`label`, `title`, `text`) and with three different letter-spacings — so
/// the same structural device looked slightly different depending on where
/// you met it.
class SectionLabel extends StatelessWidget {
  final String text;

  /// Uppercases the text. Off for labels that read as sentence case in place.
  final bool uppercase;

  const SectionLabel(this.text, {super.key, this.uppercase = true});

  @override
  Widget build(BuildContext context) {
    return Text(
      uppercase ? text.toUpperCase() : text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: uppercase ? 0.8 : 0.2,
        color: context.mutedText,
      ),
    );
  }
}
