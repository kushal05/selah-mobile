import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../l10n/l10n.dart';

/// Shows the "Join a Group" dialog.
///
/// Accepts a group code from the user and calls the join API.
/// Handles not-found, already-member, and error cases.
/// Shared between [GroupsListScreen] and the people directory.
Future<void> showJoinGroupDialog(BuildContext context, WidgetRef ref) async {
  final codeController = TextEditingController();

  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n(context).joinAGroup),
      content: TextField(
        controller: codeController,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          hintText: l10n(context).enterGroupCode,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n(context).actionCancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, codeController.text.trim()),
          child: Text(l10n(context).join),
        ),
      ],
    ),
  );
  codeController.dispose();

  if (code == null || code.isEmpty) return;
  if (!context.mounted) return;

  try {
    final joinService = ref.read(groupJoinServiceProvider);
    final result = await joinService.joinGroup(code);

    if (!context.mounted) return;

    if (result.notFound) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n(context).invalidGroupCode),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (result.alreadyMember) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n(context).youAreAlreadyAMemberOfThisGroup),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    ref.invalidate(groupsListProvider);
    ref.invalidate(groupCountProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Joined ${result.group!.name}!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFacingError.message(e, action: 'join group')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
