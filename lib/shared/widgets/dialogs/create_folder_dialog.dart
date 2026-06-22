import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/sync/models/folder_model.dart';
import '../../../core/sync/providers/sync_providers.dart';
import '../../../core/sync/repositories/folder_repository.dart';
import 'folder_dialog_helpers.dart';

/// Dialog for creating a new folder
class CreateFolderDialog extends ConsumerStatefulWidget {
  final String? parentId;
  final String? parentName;
  final String folderType;

  /// When creating a subfolder, inherit the parent's visibility.
  final FolderVisibility? parentVisibility;

  const CreateFolderDialog({
    super.key,
    this.parentId,
    this.parentName,
    this.folderType = 'note',
    this.parentVisibility,
  });

  /// Shows the create folder dialog and returns true if a folder was created
  static Future<bool?> show(
    BuildContext context, {
    String? parentId,
    String? parentName,
    String folderType = 'note',
    FolderVisibility? parentVisibility,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => CreateFolderDialog(
        parentId: parentId,
        parentName: parentName,
        folderType: folderType,
        parentVisibility: parentVisibility,
      ),
    );
  }

  @override
  ConsumerState<CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends ConsumerState<CreateFolderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nameFocusNode = FocusNode();
  bool _isCreating = false;
  String? _errorMessage;

  late FolderVisibility _selectedVisibility;
  String? _selectedGroupId;

  bool get _isSubfolder => widget.parentId != null;
  bool get _isSongType => widget.folderType == 'song';
  Color get _accentColor =>
      _isSongType ? AppTheme.orange : AppTheme.brandPurple;
  String get _entityLabel => _isSongType ? 'Songbook' : 'Folder';
  String get _entityLabelLower => _isSongType ? 'songbook' : 'folder';

  @override
  void initState() {
    super.initState();
    _selectedVisibility = widget.parentVisibility ?? FolderVisibility.personal;
    // Auto-focus the text field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
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
          Icon(
            _isSongType
                ? Icons.library_add_rounded
                : Icons.create_new_folder_rounded,
            color: _accentColor,
          ),
          const SizedBox(width: AppTheme.spacing12),
          Expanded(
            child: Text(
              _isSubfolder
                  ? 'Create Sub-$_entityLabelLower'
                  : 'Create $_entityLabel',
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.parentName != null) ...[
              Text(
                'Creating $_entityLabelLower inside "${widget.parentName}"',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: AppTheme.spacing16),
            ],
            TextFormField(
              controller: _nameController,
              focusNode: _nameFocusNode,
              decoration: folderNameFieldDecoration(
                accentColor: _accentColor,
                errorColor: colorScheme.error,
                entityLabel: _entityLabel,
                entityLabelLower: _entityLabelLower,
                errorText: _errorMessage,
              ),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textCapitalization: TextCapitalization.words,
              enabled: !_isCreating,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a $_entityLabelLower name';
                }
                return null;
              },
              onFieldSubmitted: (_) => _createFolder(),
            ),
            const SizedBox(height: AppTheme.spacing20),
            buildFolderVisibilitySelector(
              theme: theme,
              isSubfolder: _isSubfolder,
              selected: _selectedVisibility,
              accentColor: _accentColor,
              disabled: _isCreating,
              onChanged: (v) {
                setState(() {
                  _selectedVisibility = v;
                  if (v != FolderVisibility.group) {
                    _selectedGroupId = null;
                  }
                });
              },
            ),
            if (_selectedVisibility == FolderVisibility.group &&
                !_isSubfolder) ...[
              const SizedBox(height: AppTheme.spacing12),
              buildFolderGroupPicker(
                ref: ref,
                theme: theme,
                selectedGroupId: _selectedGroupId,
                selectedVisibility: _selectedVisibility,
                disabled: _isCreating,
                onChanged: (value) {
                  setState(() {
                    _selectedGroupId = value;
                  });
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating
              ? null
              : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isCreating ||
                  (_selectedVisibility == FolderVisibility.group &&
                      _selectedGroupId == null)
              ? null
              : _createFolder,
          style: FilledButton.styleFrom(backgroundColor: _accentColor),
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createFolder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final folderRepository = ref.read(folderRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);
      final name = _nameController.text.trim();

      await folderRepository.createFolder(
        name: name,
        userId: userId,
        parentId: widget.parentId,
        type: widget.folderType,
        visibility: _selectedVisibility,
        groupId: _selectedVisibility == FolderVisibility.group
            ? _selectedGroupId
            : null,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_entityLabel "$name" created'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FolderNameConflictException {
      setState(() {
        _isCreating = false;
        _errorMessage = 'A $_entityLabelLower with this name already exists';
      });
    } catch (e) {
      setState(() {
        _isCreating = false;
        _errorMessage = 'Error creating $_entityLabelLower: $e';
      });
    }
  }
}
