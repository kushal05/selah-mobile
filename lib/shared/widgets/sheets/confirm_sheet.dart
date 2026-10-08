import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_colors.dart';
import 'selah_sheet.dart';

/// Asks before doing something that matters. True only if the user confirmed.
///
/// Replaces the AlertDialog confirmations — a title, a line, and two text
/// links of equal weight, so "Delete" looked no different from "Cancel". Here
/// the action is a filled button, red when [destructive], and [message] says
/// what will actually happen: "Moves to Trash for 30 days" is a different
/// question from "This can't be undone", and the person should know which one
/// they are answering.
///
/// A swipe down, a tap outside or the back gesture all answer no.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? message,
  IconData? icon,
  Color accent = AppTheme.brandBlue,
  bool destructive = false,
  String? cancelLabel,
}) async {
  final confirmed = await showSelahSheet<bool>(
    context,
    builder: (sheetContext) => SelahSheet(
      title: title,
      icon: icon,
      accent: accent,
      destructive: destructive,
      body: message == null
          ? null
          : Text(
              message,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: sheetContext.mutedText,
              ),
            ),
      primaryLabel: confirmLabel,
      onPrimary: () => Navigator.of(sheetContext).pop(true),
      cancelLabel: cancelLabel,
      onCancel: () => Navigator.of(sheetContext).pop(false),
    ),
  );
  return confirmed ?? false;
}
