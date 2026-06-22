import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/sync/models/folder_model.dart';
import '../../../core/sync/providers/sync_providers.dart';
import '../../../core/sync/repositories/folder_repository.dart';
import 'folder_dialog_helpers.dart';

/// Dialog for editing a folder's name, visibility, and group.
/// Subfolders inherit visibility from their parent — visibility controls are
/// disabled in that case. Changing visibility on a root folder cascades to all
/// descendants (handled by [FolderRepository.updateFolder]).
class EditFolderDialog extends ConsumerStatefulWidget {
  final FolderModel folder;

  const EditFolderDialog({super.key, required this.folder});

  static Future<bool?> show(BuildContext context, FolderModel folder) {
    return showDialog<bool>(
      context: context,
      builder: (context) => EditFolderDialog(folder: folder),
    );
  }

  @override
  ConsumerState<EditFolderDialog> createState() => _EditFolderDialogState();
}

class _EditFolderDialogState extends ConsumerState<EditFolderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _nameFocusNode = FocusNode();
  bool _isSaving = false;
  String? _errorMessage;

  late FolderVisibility _selectedVisibility;
  String? _selectedGroupId;

  bool get _isSubfolder => widget.folder.parentId != null;
  bool get _isSongType => widget.folder.type == 'song';
  Color get _accentColor =>
      _isSongType ? AppTheme.orange : AppTheme.brandPurple;
  String get _entityLabel => _isSongType ? 'Songbook' : 'Folder';
  String get _entityLabelLower => _isSongType ? 'songbook' : 'folder';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.folder.name);
    _selectedVisibility = widget.folder.visibility;
    _selectedGroupId = widget.folder.groupId;
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

  bool get _hasChanges {
    if (_nameController.text.trim() != widget.folder.name) return true;
    if (_isSubfolder) return false;
    if (_selectedVisibility != widget.folder.visibility) return true;
    final newGroupId =
        _selectedVisibility == FolderVisibility.group ? _selectedGroupId : null;
    final existingGroupId = widget.folder.visibility == FolderVisibility.group
        ? widget.folder.groupId
        : null;
    return newGroupId != existingGroupId;
  }

  bool get _canSave =>
      !_isSaving &&
      _hasChanges &&
      !(!_isSubfolder &&
          _selectedVisibility == FolderVisibility.group &&
          _selectedGroupId == null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit_rounded, color: _accentColor),
          const SizedBox(width: AppTheme.spacing12),
          Expanded(child: Text('Edit $_entityLabel')),
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
              decoration: folderNameFieldDecoration(
                accentColor: _accentColor,
                errorColor: colorScheme.error,
                entityLabel: _entityLabel,
                entityLabelLower: _entityLabelLower,
                errorText: _errorMessage,
              ),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textCapitalization: TextCapitalization.words,
              enabled: !_isSaving,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a $_entityLabelLower name';
                }
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppTheme.spacing20),
            buildFolderVisibilitySelector(
              theme: theme,
              isSubfolder: _isSubfolder,
              selected: _selectedVisibility,
              accentColor: _accentColor,
              disabled: _isSaving,
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
                disabled: _isSaving,
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
          onPressed:
              _isSaving ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: _nameController,
          builder: (context, _) => FilledButton(
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(backgroundColor: _accentColor),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final folderRepository = ref.read(folderRepositoryProvider);
      await folderRepository.updateFolder(
        id: widget.folder.id,
        name: _nameController.text.trim(),
        visibility: _isSubfolder ? null : _selectedVisibility,
        groupId: !_isSubfolder && _selectedVisibility == FolderVisibility.group
            ? _selectedGroupId
            : null,
        clearGroupId:
            !_isSubfolder && _selectedVisibility != FolderVisibility.group,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_entityLabel updated'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FolderNameConflictException {
      setState(() {
        _isSaving = false;
        _errorMessage = 'A $_entityLabelLower with this name already exists';
      });
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = 'Error updating $_entityLabelLower: $e';
      });
    }
  }
}
