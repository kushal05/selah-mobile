import 'package:flutter/material.dart';

import '../../../../core/sync/models/group_member_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// Nominates the member who inherits a group when its last admin leaves.
///
/// Only shown when there is a real choice to make. With one other member the
/// server promotes them without asking, and with none there is nothing to hand
/// over — the group simply becomes an archive of what it was.
///
/// Returns the chosen membership id, or null if the person backed out, which
/// cancels the departure rather than leaving without a successor.
class ChooseSuccessorDialog extends StatefulWidget {
  final List<GroupMemberModel> candidates;

  const ChooseSuccessorDialog({super.key, required this.candidates});

  static Future<String?> show(
    BuildContext context,
    List<GroupMemberModel> candidates,
  ) {
    return showDialog<String>(
      context: context,
      builder: (context) => ChooseSuccessorDialog(candidates: candidates),
    );
  }

  @override
  State<ChooseSuccessorDialog> createState() => _ChooseSuccessorDialogState();
}

class _ChooseSuccessorDialogState extends State<ChooseSuccessorDialog> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n(context).chooseTheNextAdmin),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n(context).youAreTheOnlyAdminPickWhoTakesOver,
              style: TextStyle(color: context.mutedText, fontSize: 14),
            ),
            const SizedBox(height: AppTheme.spacing12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.candidates.length,
                itemBuilder: (context, index) {
                  final member = widget.candidates[index];
                  final selected = member.id == _selectedId;
                  // A ListTile rather than RadioListTile: the radio's
                  // groupValue/onChanged are deprecated in this Flutter in
                  // favour of a RadioGroup ancestor, and drawing the mark
                  // directly keeps the dialog working either way.
                  return ListTile(
                    onTap: () => setState(() => _selectedId = member.id),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : context.mutedText,
                    ),
                    title: Text(member.displayName),
                    subtitle: Text('@${member.memberUsername}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n(context).actionCancel),
        ),
        TextButton(
          // Disabled until somebody is chosen: leaving without a successor is
          // what the server refuses, and offering the button would only
          // produce an error the person cannot act on.
          onPressed: _selectedId == null
              ? null
              : () => Navigator.pop(context, _selectedId),
          child: Text(l10n(context).setAsAdmin),
        ),
      ],
    );
  }
}
