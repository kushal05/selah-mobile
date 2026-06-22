import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/models/folder_model.dart';
import '../../../core/sync/providers/sync_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Shared building blocks for folder create/edit dialogs.
/// Keeps the visibility + group selection UI consistent between
/// [CreateFolderDialog] and [EditFolderDialog].

InputDecoration folderNameFieldDecoration({
  required Color accentColor,
  required Color errorColor,
  required String entityLabel,
  required String entityLabelLower,
  String? errorText,
}) {
  return InputDecoration(
    labelText: '$entityLabel name',
    hintText: 'Enter $entityLabelLower name',
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
        color: accentColor.withValues(alpha: 0.3),
        width: AppTheme.borderWidthDefault,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: AppTheme.borderRadius3XL,
      borderSide: BorderSide(
        color: errorColor.withValues(alpha: 0.5),
        width: AppTheme.borderWidthDefault,
      ),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: AppTheme.borderRadius3XL,
      borderSide: BorderSide(
        color: errorColor.withValues(alpha: 0.5),
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
    errorText: errorText,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppTheme.spacing16,
      vertical: AppTheme.spacing16,
    ),
  );
}

/// Visibility chip row. When [isSubfolder] is true, renders a single
/// read-only chip instead — subfolders inherit visibility from their parent.
Widget buildFolderVisibilitySelector({
  required ThemeData theme,
  required bool isSubfolder,
  required FolderVisibility selected,
  required Color accentColor,
  required bool disabled,
  required ValueChanged<FolderVisibility> onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Visibility',
        style: theme.textTheme.labelMedium?.copyWith(
          color: AppTheme.gray700,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: AppTheme.spacing8),
      if (isSubfolder)
        Wrap(
          children: [
            Chip(
              avatar: Icon(selected.icon, size: AppTheme.iconMD),
              label: Text(
                '${selected.displayName} (inherited)',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FolderVisibility.values.map((v) {
            final isSelected = selected == v;
            return ChoiceChip(
              label: Text(v.displayName),
              avatar: Icon(
                v.icon,
                size: 16,
                color: isSelected ? accentColor : Colors.grey.shade600,
              ),
              selected: isSelected,
              onSelected: disabled
                  ? null
                  : (s) {
                      if (s) onChanged(v);
                    },
              selectedColor: accentColor.withValues(alpha: 0.12),
              backgroundColor: Colors.grey.shade50,
              side: BorderSide(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.4)
                    : Colors.grey.shade300,
              ),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? accentColor : Colors.grey.shade700,
              ),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
    ],
  );
}

Widget buildFolderGroupPicker({
  required WidgetRef ref,
  required ThemeData theme,
  required String? selectedGroupId,
  required FolderVisibility selectedVisibility,
  required bool disabled,
  required ValueChanged<String?> onChanged,
}) {
  final groupsAsync = ref.watch(groupsListProvider);

  return groupsAsync.when(
    data: (groups) {
      if (groups.isEmpty) {
        return Text(
          'No groups available. Create a group first.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.orange.shade700,
          ),
        );
      }

      final valueExists = groups.any((g) => g.id == selectedGroupId);
      return DropdownButtonFormField<String>(
        initialValue: valueExists ? selectedGroupId : null,
        decoration: InputDecoration(
          labelText: 'Select Group',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          filled: true,
          fillColor: AppTheme.inputFillColor,
          prefixIcon: Icon(Icons.group_outlined, color: AppTheme.hintColor),
          border: OutlineInputBorder(
            borderRadius: AppTheme.borderRadius3XL,
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing16,
            vertical: AppTheme.spacing12,
          ),
        ),
        items: groups.map((group) {
          return DropdownMenuItem<String>(
            value: group.id,
            child: Text(group.name),
          );
        }).toList(),
        onChanged: disabled ? null : onChanged,
        validator: (value) {
          if (selectedVisibility == FolderVisibility.group && value == null) {
            return 'Please select a group';
          }
          return null;
        },
      );
    },
    loading: () => const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
    error: (_, _) => Text(
      'Could not load groups',
      style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
    ),
  );
}
