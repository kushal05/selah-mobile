import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// Shows a confirmation that an item was moved to Trash, with an Undo action.
///
/// Recovery at the moment of the mistake, rather than a confirmation dialog
/// before it. Confirmation dialogs are dismissed reflexively and add friction
/// to every action to guard against a rare one; an Undo costs nothing until it
/// is needed, and tells the user where the item went if it is not.
///
/// [itemLabel] names what was removed ('Prayer', 'Note', 'Song'), so the
/// message reads as a specific fact rather than a generic acknowledgement.
/// [onUndo] should restore the item; anything it throws is surfaced to the
/// user rather than swallowed, since a failed undo is exactly the case where
/// silence would be worst.
void showUndoSnackBar(
  BuildContext context, {
  required String itemLabel,
  required Future<void> Function() onUndo,
  String? customMessage,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(customMessage ?? '$itemLabel moved to Trash'),
      // Long enough to notice, read and act on — the default 4s is short for
      // an older or slower reader, who is also the likeliest to need Undo.
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: l10n(context).actionUndo,
        onPressed: () async {
          try {
            await onUndo();
            messenger
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text('$itemLabel restored'),
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          } catch (_) {
            messenger
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    "Couldn't restore that $itemLabel. "
                    'You can still find it in Settings → Trash.',
                  ),
                  duration: const Duration(seconds: 6),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: AppTheme.errorSurface,
                ),
              );
          }
        },
      ),
    ),
  );
}
