import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/sync/models/folder_model.dart';
import '../../../core/sync/providers/sync_providers.dart';
import '../../../core/sync/repositories/folder_repository.dart';

/// Dialog for renaming a folder
class RenameFolderDialog extends ConsumerStatefulWidget {
  final FolderModel folder;

  const RenameFolderDialog({
    super.key,
    required this.folder,
  });

  /// Shows the rename folder dialog and returns true if the folder was renamed
  static Future<bool?> show(BuildContext context, FolderModel folder) {
    return showDialog<bool>(
      context: context,
      builder: (context) => RenameFolderDialog(folder: folder),
    );
  }

  @override
  ConsumerState<RenameFolderDialog> createState() => _RenameFolderDialogState();
}

class _RenameFolderDialogState extends ConsumerState<RenameFolderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _nameFocusNode = FocusNode();
  bool _isRenaming = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.folder.name);
    // Select all text and focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_rounded, color: AppTheme.brandPurple),
          const SizedBox(width: AppTheme.spacing12),
          const Expanded(child: Text('Rename Folder')),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              decoration: InputDecoration(
                labelText: 'Folder name',
                hintText: 'Enter new name',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                filled: true,
                fillColor: AppTheme.inputFillColor,
                prefixIcon: Icon(Icons.folder_outlined, color: AppTheme.hintColor),
                border: OutlineInputBorder(
                  borderRadius: AppTheme.borderRadius3XL,
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppTheme.borderRadius3XL,
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppTheme.borderRadius3XL,
                  borderSide: BorderSide(
                    color: AppTheme.brandPurple.withValues(alpha: 0.3),
                    width: AppTheme.borderWidthDefault,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: AppTheme.borderRadius3XL,
                  borderSide: BorderSide(
                    color: colorScheme.error.withValues(alpha: 0.5),
                    width: AppTheme.borderWidthDefault,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: AppTheme.borderRadius3XL,
                  borderSide: BorderSide(
                    color: colorScheme.error.withValues(alpha: 0.5),
                    width: AppTheme.borderWidthDefault,
                  ),
                ),
                labelStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.gray700,
                ),
                hintStyle: TextStyle(
                  fontSize: AppTheme.headingSmall.fontSize,
                  color: AppTheme.hintColor,
                ),
                errorText: _errorMessage,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: AppTheme.spacing16),
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_isRenaming,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a folder name';
                }
                if (value.trim() == widget.folder.name) {
                  return 'Please enter a different name';
                }
                return null;
              },
              onFieldSubmitted: (_) => _renameFolder(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRenaming ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isRenaming ? null : _renameFolder,
          child: _isRenaming
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Rename'),
        ),
      ],
    );
  }

  Future<void> _renameFolder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isRenaming = true;
      _errorMessage = null;
    });

    try {
      final folderRepository = ref.read(folderRepositoryProvider);
      final newName = _nameController.text.trim();

      await folderRepository.updateFolder(
        id: widget.folder.id,
        name: newName,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Folder renamed to "$newName"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FolderNameConflictException {
      setState(() {
        _isRenaming = false;
        _errorMessage = 'A folder with this name already exists';
      });
    } catch (e) {
      setState(() {
        _isRenaming = false;
        _errorMessage = 'Error renaming folder: $e';
      });
    }
  }
}
