import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/models/person_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';

/// Screen for adding or editing a person
/// Provides form fields for name, relation, church, notes, and tags
class AddPersonScreen extends ConsumerStatefulWidget {
  final String? personId;

  const AddPersonScreen({super.key, this.personId});

  bool get isEditMode => personId != null;

  @override
  ConsumerState<AddPersonScreen> createState() => _AddPersonScreenState();
}

class _AddPersonScreenState extends ConsumerState<AddPersonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _churchController = TextEditingController();

  String? _relation;
  final List<String> _tags = [];
  bool _isAddingTag = false;
  final _tagController = TextEditingController();
  final _tagInputFocusNode = FocusNode();
  PersonModel? _existingPerson;

  final List<String> _relationOptions = [
    'Family',
    'Friend',
    'Church Member',
    'Colleague',
    'Neighbor',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _loadPersonData();
    }
  }

  Future<void> _loadPersonData() async {
    if (widget.personId == null) return;

    final repository = ref.read(personRepositoryProvider);
    final person = await repository.getPersonById(widget.personId!);

    if (mounted && person != null) {
      setState(() {
        _existingPerson = person;
        _nameController.text = person.name;
        _relation = person.relation.isNotEmpty ? person.relation : null;
        _churchController.text = person.church ?? '';
        _notesController.text = person.notes;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _churchController.dispose();
    _tagController.dispose();
    _tagInputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _handleClose(context),
        ),
        title: Text(widget.isEditMode ? 'Edit Person' : 'New Person'),
        actions: [
          TextButton(
            onPressed: _handleSave,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name field
                _buildNameField(),
                const SizedBox(height: 24),

                // Relation selector
                _buildRelationSelector(),
                const SizedBox(height: 24),

                // Church field
                _buildChurchField(),
                const SizedBox(height: 24),

                // Notes field
                _buildNotesField(),
                const SizedBox(height: 24),

                // Tags section
                _buildTagsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: 'Name',
        hintText: 'Enter person\'s name',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixIcon: Icon(Icons.person_outline, color: Colors.grey.shade400),
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
          borderSide: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), width: 1.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), width: 1.0),
        ),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
        hintStyle: TextStyle(
          fontSize: 15,
          color: Colors.grey.shade400,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a name';
        }
        return null;
      },
    );
  }

  Widget _buildRelationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Relation',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _relationOptions.map((relation) {
            final isSelected = _relation == relation;
            return ChoiceChip(
              label: Text(relation),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  FocusScope.of(context).unfocus();
                  setState(() => _relation = relation);
                }
              },
              selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
                      : Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  width: 1.0,
                ),
              ),
              labelStyle: TextStyle(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChurchField() {
    return TextFormField(
      controller: _churchController,
      decoration: InputDecoration(
        labelText: 'Church/Organization',
        hintText: 'Enter church or organization name',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixIcon: Icon(Icons.church_outlined, color: Colors.grey.shade400),
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
          borderSide: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), width: 1.0),
        ),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
        hintStyle: TextStyle(
          fontSize: 15,
          color: Colors.grey.shade400,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      decoration: InputDecoration(
        labelText: 'Notes',
        hintText: 'Add any notes about this person...',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        alignLabelWithHint: true,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(bottom: 64),
          child: Icon(Icons.notes_outlined, color: Colors.grey.shade400),
        ),
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
          borderSide: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), width: 1.0),
        ),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
        hintStyle: TextStyle(
          fontSize: 15,
          color: Colors.grey.shade400,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      maxLines: 5,
      minLines: 3,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(
        fontSize: 15,
        height: 1.5,
      ),
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._tags.map((tag) => _SelectableChip(
                  label: tag,
                  isSelected: true,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _tags.remove(tag));
                  },
                  showDelete: true,
                )),
          ],
        ),
        const SizedBox(height: 12),
        if (_isAddingTag)
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    focusNode: _tagInputFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Enter tag name...',
                      prefixIcon: Icon(Icons.label_outline, size: 20, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.transparent,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: _submitTag,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.check,
                    color: Theme.of(context).primaryColor,
                  ),
                  onPressed: () => _submitTag(_tagController.text),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: Colors.grey.shade500,
                  ),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _isAddingTag = false;
                      _tagController.clear();
                    });
                  },
                ),
              ],
            ),
          )
        else
          TextButton.icon(
            onPressed: () {
              setState(() => _isAddingTag = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _tagInputFocusNode.requestFocus();
              });
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add tag'),
          ),
      ],
    );
  }

  void _submitTag(String tag) {
    final trimmed = tag.trim();
    FocusScope.of(context).unfocus();
    if (trimmed.isNotEmpty && !_tags.contains(trimmed)) {
      setState(() {
        _tags.add(trimmed);
        _tagController.clear();
        _isAddingTag = false;
      });
    } else {
      setState(() {
        _tagController.clear();
        _isAddingTag = false;
      });
    }
  }

  void _handleClose(BuildContext context) {
    if (_nameController.text.isNotEmpty ||
        _notesController.text.isNotEmpty ||
        _churchController.text.isNotEmpty ||
        _tags.isNotEmpty ||
        _relation != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('You have unsaved changes. Are you sure you want to discard them?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.pop();
              },
              child: const Text('Discard'),
            ),
          ],
        ),
      );
    } else {
      context.pop();
    }
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        final repository = ref.read(personRepositoryProvider);
        final userId = ref.read(currentUserIdProvider);

        if (widget.isEditMode && _existingPerson != null) {
          // Update existing person
          await repository.updatePerson(
            id: widget.personId!,
            name: _nameController.text.trim(),
            relation: _relation ?? '',
            church: _churchController.text.trim().isNotEmpty
                ? _churchController.text.trim()
                : null,
            notes: _notesController.text.trim(),
          );
        } else {
          // Create new person
          await repository.createPerson(
            userId: userId,
            name: _nameController.text.trim(),
            relation: _relation ?? '',
            church: _churchController.text.trim().isNotEmpty
                ? _churchController.text.trim()
                : null,
            notes: _notesController.text.trim(),
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.isEditMode
                  ? 'Person updated successfully'
                  : 'Person saved successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving person: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

/// A selectable chip widget for tags
class _SelectableChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showDelete;

  const _SelectableChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.showDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
            if (showDelete && isSelected) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.close,
                size: 16,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
