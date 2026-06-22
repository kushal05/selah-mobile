import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';

/// Shows the "Join a Group" dialog.
///
/// Accepts a group code from the user and calls the join API.
/// Handles not-found, already-member, and error cases.
/// Shared between [GroupsListScreen] and [SocialHomeScreen].
Future<void> showJoinGroupDialog(BuildContext context, WidgetRef ref) async {
  final codeController = TextEditingController();

  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Join a Group'),
      content: TextField(
        controller: codeController,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          hintText: 'Enter group code',
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
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, codeController.text.trim()),
          child: const Text('Join'),
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
        const SnackBar(
          content: Text('Invalid group code'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (result.alreadyMember) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are already a member of this group'),
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
          content: Text('Failed to join group: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
