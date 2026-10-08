import 'package:flutter/material.dart';

import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/sheets/sheets.dart';

/// Records that a prayer was prayed, with an optional note.
///
/// This was a bare [AlertDialog] — a title, an undecorated TextField and two
/// text buttons — on an action that is the emotional centre of the app. It is
/// a sheet now, and the design every other dialog is moving to ([SelahSheet]
/// was taken from it): the prayer being logged is named, the note field looks
/// like a place to write, and the confirming action is a filled button rather
/// than one of two identical links.
///
/// Returns the note (possibly empty) when logged, or null if dismissed.
Future<String?> showLogPrayerSheet(
  BuildContext context, {
  required String prayerTitle,
}) {
  return showSelahSheet<String>(
    context,
    builder: (_) => _LogPrayerSheet(prayerTitle: prayerTitle),
  );
}

/// Not [showInputSheet]: the note is optional, so there is nothing to
/// validate, and the field should not grab focus. Most logs carry no note;
/// opening on a keyboard would put typing in the way of the one tap most
/// people came for, and the sheet never did before.
class _LogPrayerSheet extends StatefulWidget {
  final String prayerTitle;
  const _LogPrayerSheet({required this.prayerTitle});

  @override
  State<_LogPrayerSheet> createState() => _LogPrayerSheetState();
}

class _LogPrayerSheetState extends State<_LogPrayerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    // The dialog this replaces created a TextEditingController in a build
    // method and never disposed it.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = l10n(context);
    return SelahSheet(
      title: strings.markThisTimeOfPrayer,
      // Naming the prayer removes the "which one is this?" question the bare
      // dialog left open.
      subtitle: widget.prayerTitle,
      icon: Icons.check_rounded,
      body: TextField(
        controller: _controller,
        minLines: 3,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 16, height: 1.4),
        decoration:
            selahFieldDecoration(context, hint: strings.howDidItGoOptional),
      ),
      primaryLabel: strings.logPrayer,
      primaryIcon: Icons.check_rounded,
      onPrimary: () => Navigator.of(context).pop(_controller.text.trim()),
    );
  }
}
