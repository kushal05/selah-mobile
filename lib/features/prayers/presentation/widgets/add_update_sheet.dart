import 'package:flutter/material.dart';

import '../../../../core/sync/models/prayer_collaborator_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/sheets/sheets.dart';

/// Asks for an update on a prayer: what has happened, what has changed.
///
/// Returns the text, trimmed, or null if the sheet was dismissed.
///
/// This was a sheet of its own with light-theme colours written into it — a
/// near-white field (#FBFAFA) and a pale grey hint — so in dark mode it showed
/// a white slab with the dark theme's light text barely visible on it. Built on
/// [SelahSheet] now, every colour comes from the theme. Add stays disabled
/// until there is something to add; it used to accept the tap and do nothing.
///
/// [collaborators], when there are any, get a row of @-mention chips.
Future<String?> showAddUpdateSheet(
  BuildContext context, {
  required String prayerTitle,
  required List<PrayerCollaboratorModel> collaborators,
}) {
  return showSelahSheet<String>(
    context,
    builder: (_) => _AddUpdateSheet(
      prayerTitle: prayerTitle,
      collaborators: collaborators,
    ),
  );
}

class _AddUpdateSheet extends StatefulWidget {
  final String prayerTitle;
  final List<PrayerCollaboratorModel> collaborators;

  const _AddUpdateSheet({
    required this.prayerTitle,
    required this.collaborators,
  });

  @override
  State<_AddUpdateSheet> createState() => _AddUpdateSheetState();
}

class _AddUpdateSheetState extends State<_AddUpdateSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    // The sheet this replaces created its controller per open and never
    // disposed it.
    _controller.dispose();
    super.dispose();
  }

  String get _text => _controller.text.trim();

  /// Puts "@username " at the cursor, or at the end if there is none.
  void _insertMention(String username) {
    final text = _controller.text;
    final selection = _controller.selection;
    final offset = selection.isValid ? selection.baseOffset : text.length;
    final mention = '@$username ';
    _controller.value = TextEditingValue(
      text: text.substring(0, offset) + mention + text.substring(offset),
      selection: TextSelection.collapsed(offset: offset + mention.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final strings = l10n(context);
    final mentionInk = context.accentInk(AppTheme.brandPurple);
    return SelahSheet(
      title: strings.addUpdate,
      subtitle: widget.prayerTitle,
      icon: Icons.edit_note_rounded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 16, height: 1.4),
            decoration: selahFieldDecoration(
              context,
              hint: strings.writeYourUpdateHere,
            ),
          ),
          if (widget.collaborators.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.alternate_email, size: 18, color: context.mutedText),
                for (final c in widget.collaborators)
                  ActionChip(
                    label: Text(
                      '@${c.collaboratorUsername}',
                      style: TextStyle(fontSize: 13, color: mentionInk),
                    ),
                    onPressed: () => _insertMention(c.collaboratorUsername),
                    backgroundColor:
                        AppTheme.brandPurple.withValues(alpha: AppTheme.alphaLight),
                    side: BorderSide.none,
                  ),
              ],
            ),
          ],
        ],
      ),
      primaryLabel: strings.add,
      primaryIcon: Icons.add_rounded,
      onPrimary:
          _text.isEmpty ? null : () => Navigator.of(context).pop(_text),
    );
  }
}
