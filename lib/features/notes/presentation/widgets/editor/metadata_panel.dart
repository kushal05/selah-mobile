import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/sync/providers/sync_providers.dart';
import '../../../../../shared/widgets/drag_handle.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../providers/note_editor_provider.dart';
import '../../../../../shared/widgets/skeletons/skeletons.dart';

/// Shows the metadata panel as a bottom sheet
Future<void> showMetadataPanel(BuildContext context, String? noteId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => MetadataPanel(noteId: noteId),
  );
}

/// Metadata panel for editing note metadata (date, preacher, tags)
class MetadataPanel extends ConsumerStatefulWidget {
  final String? noteId;

  const MetadataPanel({super.key, required this.noteId});

  @override
  ConsumerState<MetadataPanel> createState() => _MetadataPanelState();
}

class _MetadataPanelState extends ConsumerState<MetadataPanel> {
  final _tagController = TextEditingController();

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(noteEditorProvider(widget.noteId));
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              const DragHandle(),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      'Note Details',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Date picker
                    _MetadataSection(
                      title: 'Date',
                      child: _DatePickerField(
                        value: editorState.noteDate,
                        onChanged: (date) {
                          ref.read(noteEditorProvider(widget.noteId).notifier).setNoteDate(date);
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Preacher selector
                    _MetadataSection(
                      title: 'Preacher',
                      child: _PreacherSelector(
                        noteId: widget.noteId,
                        selectedPreacherId: editorState.preacherId,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Tags
                    _MetadataSection(
                      title: 'Tags',
                      child: _TagSelector(
                        noteId: widget.noteId,
                        selectedTagIds: editorState.tagIds,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetadataSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _MetadataSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DatePickerField({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _selectDate(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 20,
              color: AppTheme.brandPurple,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value != null ? _formatDate(value!) : 'Select date...',
                style: TextStyle(
                  color: value != null ? null : Colors.grey.shade500,
                ),
              ),
            ),
            if (value != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () => onChanged(null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      onChanged(selected);
    }
  }
}

class _PreacherSelector extends ConsumerWidget {
  final String? noteId;
  final String? selectedPreacherId;

  const _PreacherSelector({
    required this.noteId,
    required this.selectedPreacherId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peopleAsync = ref.watch(peopleStreamProvider);

    return peopleAsync.when(
      loading: () => const Column(children: [ListTileSkeleton(), ListTileSkeleton()]),
      error: (error, _) => Text('Error loading people: $error'),
      data: (people) {
        if (people.isEmpty) {
          return _EmptyPeoplePrompt(
            onPersonAdded: (personId) {
              ref.read(noteEditorProvider(noteId).notifier).setPreacher(personId);
            },
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final person in people)
                  _SelectableChip(
                    label: person.name,
                    isSelected: selectedPreacherId == person.id,
                    onTap: () {
                      final newId = selectedPreacherId == person.id ? null : person.id;
                      ref.read(noteEditorProvider(noteId).notifier).setPreacher(newId);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _AddPersonButton(
              onPersonAdded: (personId) {
                ref.read(noteEditorProvider(noteId).notifier).setPreacher(personId);
              },
            ),
          ],
        );
      },
    );
  }
}

/// Shown when there are no people in the People section
class _EmptyPeoplePrompt extends StatelessWidget {
  final ValueChanged<String> onPersonAdded;

  const _EmptyPeoplePrompt({required this.onPersonAdded});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 32, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            'No people added yet',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a person to select as preacher',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 12),
          _AddPersonButton(onPersonAdded: onPersonAdded),
        ],
      ),
    );
  }
}

/// Button that shows a dialog to quickly add a person
class _AddPersonButton extends ConsumerWidget {
  final ValueChanged<String> onPersonAdded;

  const _AddPersonButton({required this.onPersonAdded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => _showAddPersonDialog(context, ref),
      style: TextButton.styleFrom(foregroundColor: AppTheme.brandPurple),
      icon: const Icon(Icons.person_add, size: 18),
      label: const Text('Add person'),
    );
  }

  Future<void> _showAddPersonDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Person'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Enter person\'s name',
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(context).pop(value.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(context).pop(name);
                }
              },
              style: TextButton.styleFrom(foregroundColor: AppTheme.brandPurple),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result != null && context.mounted) {
      final repository = ref.read(personRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);
      final person = await repository.createPerson(userId: userId, name: result);
      onPersonAdded(person.id);
    }
  }
}

class _TagSelector extends ConsumerWidget {
  final String? noteId;
  final List<String> selectedTagIds;

  const _TagSelector({
    required this.noteId,
    required this.selectedTagIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsStreamProvider);

    return tagsAsync.when(
      loading: () => const Column(children: [ListTileSkeleton(hasLeading: false), ListTileSkeleton(hasLeading: false)]),
      error: (error, _) => Text('Error loading tags: $error'),
      data: (tags) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Existing tags
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  _SelectableChip(
                    label: tag.name,
                    isSelected: selectedTagIds.contains(tag.id),
                    onTap: () {
                      final newTagIds = List<String>.from(selectedTagIds);
                      if (selectedTagIds.contains(tag.id)) {
                        newTagIds.remove(tag.id);
                      } else {
                        newTagIds.add(tag.id);
                      }
                      ref.read(noteEditorProvider(noteId).notifier).setTags(newTagIds);
                    },
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Add new tag
            _AddNewButton(
              label: 'Add tag',
              onAdd: (name) async {
                final tagRepo = ref.read(tagRepositoryProvider);
                final userId = ref.read(currentUserIdProvider);
                final tag = await tagRepo.getOrCreateTag(name, userId);
                if (context.mounted) {
                  final newTagIds = [...selectedTagIds, tag.id];
                  ref.read(noteEditorProvider(noteId).notifier).setTags(newTagIds);
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _SelectableChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SelectableChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.brandPurple : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

class _AddNewButton extends StatefulWidget {
  final String label;
  final Future<void> Function(String name) onAdd;

  const _AddNewButton({
    required this.label,
    required this.onAdd,
  });

  @override
  State<_AddNewButton> createState() => _AddNewButtonState();
}

class _AddNewButtonState extends State<_AddNewButton> {
  bool _isEditing = false;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Enter name...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppTheme.brandPurple.withValues(alpha: 0.25), width: 1.0),
                ),
              ),
              onSubmitted: _submit,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => _submit(_controller.text),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _isEditing = false;
                _controller.clear();
              });
            },
          ),
        ],
      );
    }

    return TextButton.icon(
      onPressed: () {
        setState(() => _isEditing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      },
      style: TextButton.styleFrom(foregroundColor: AppTheme.brandPurple),
      icon: const Icon(Icons.add, size: 18),
      label: Text(widget.label),
    );
  }

  void _submit(String value) {
    final name = value.trim();
    if (name.isEmpty) return;

    widget.onAdd(name);
    setState(() {
      _isEditing = false;
      _controller.clear();
    });
  }
}
