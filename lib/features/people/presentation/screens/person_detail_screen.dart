import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/person_model.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../prayers/presentation/screens/prayer_detail_screen.dart';

/// Person detail screen with inline editing for all fields.
/// All changes auto-save on field blur.
class PersonDetailScreen extends ConsumerStatefulWidget {
  final String personId;

  const PersonDetailScreen({super.key, required this.personId});

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  bool _controllersInitialized = false;

  // Editing state per field
  String? _editingField; // null, 'name', 'church', 'email', 'phone', 'notes'

  late TextEditingController _nameController;
  late TextEditingController _churchController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _notesController;

  final _nameFocus = FocusNode();
  final _churchFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _notesFocus = FocusNode();

  static const _relationOptions = [
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
    _nameController = TextEditingController();
    _churchController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _notesController = TextEditingController();
  }

  /// Initialize controllers from person data on first load.
  void _initControllersFromPerson(PersonModel person) {
    if (_controllersInitialized) return;
    _controllersInitialized = true;
    _nameController.text = person.name;
    _churchController.text = person.church ?? '';
    _emailController.text = person.email ?? '';
    _phoneController.text = person.phone ?? '';
    _notesController.text = person.notes;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _churchController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _nameFocus.dispose();
    _churchFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  // ── Save helpers ──

  Future<void> _saveField(String field) async {
    final currentPerson = ref.read(personByIdProvider(widget.personId)).valueOrNull;
    if (currentPerson == null) return;
    setState(() => _editingField = null);

    final repo = ref.read(personRepositoryProvider);
    try {
      bool didUpdate = false;
      switch (field) {
        case 'name':
          final v = _nameController.text.trim();
          if (v.isEmpty || v == currentPerson.name) return;
          await repo.updatePerson(id: widget.personId, name: v);
          didUpdate = true;
        case 'church':
          final v = _churchController.text.trim();
          if (v == (currentPerson.church ?? '')) return;
          await repo.updatePerson(
              id: widget.personId, church: v.isEmpty ? null : v);
          didUpdate = true;
        case 'email':
          final v = _emailController.text.trim();
          if (v == (currentPerson.email ?? '')) return;
          await repo.updatePerson(
              id: widget.personId, email: v.isEmpty ? null : v);
          didUpdate = true;
        case 'phone':
          final v = _phoneController.text.trim();
          if (v == (currentPerson.phone ?? '')) return;
          await repo.updatePerson(
              id: widget.personId, phone: v.isEmpty ? null : v);
          didUpdate = true;
        case 'notes':
          final v = _notesController.text.trim();
          if (v == currentPerson.notes) return;
          await repo.updatePerson(id: widget.personId, notes: v);
          didUpdate = true;
      }
      if (mounted && didUpdate) {
        ref.invalidate(personByIdProvider(widget.personId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  Future<void> _saveRelation(String relation) async {
    final currentPerson = ref.read(personByIdProvider(widget.personId)).valueOrNull;
    if (currentPerson == null || relation == currentPerson.relation) return;
    try {
      final repo = ref.read(personRepositoryProvider);
      await repo.updatePerson(id: widget.personId, relation: relation);
      if (mounted) {
        ref.invalidate(personByIdProvider(widget.personId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  void _startEditing(String field, FocusNode focus) {
    // Save any currently editing field first
    if (_editingField != null && _editingField != field) {
      _saveField(_editingField!);
    }
    setState(() => _editingField = field);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus.requestFocus();
    });
  }

  // ── Delete ──

  Future<void> _deletePerson() async {
    try {
      final repository = ref.read(personRepositoryProvider);
      await repository.trashPerson(widget.personId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Moved to trash')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: const Text('Are you sure you want to move this person to trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePerson();
            },
            child: const Text('Move to Trash', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final personAsync = ref.watch(personByIdProvider(widget.personId));

    return personAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        body: const DetailPageSkeleton(),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Error loading person: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(personByIdProvider(widget.personId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (person) {
        if (person == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
            ),
            body: const Center(child: Text('Person not found')),
          );
        }

        _initControllersFromPerson(person);
        return _buildPersonDetail(context, person);
      },
    );
  }

  Widget _buildPersonDetail(BuildContext context, PersonModel person) {
    return GestureDetector(
      onTap: () {
        // Save any editing field when tapping outside
        if (_editingField != null) {
          _saveField(_editingField!);
        }
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_editingField != null) _saveField(_editingField!);
              Navigator.of(context).pop();
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _showDeleteConfirmation,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + Name
                _buildHeader(person),
                const SizedBox(height: 24),

                // Relation
                _buildRelationSection(person),
                const SizedBox(height: 24),

                // Editable detail fields
                _buildEditableField(
                  field: 'church',
                  icon: Icons.church_outlined,
                  label: 'Church / Organization',
                  controller: _churchController,
                  focusNode: _churchFocus,
                  capitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                _buildEditableField(
                  field: 'email',
                  icon: Icons.email_outlined,
                  label: 'Email',
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                _buildEditableField(
                  field: 'phone',
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),

                // Notes
                _buildNotesSection(person),
                const SizedBox(height: 24),

                // Linked prayers
                _buildLinkedPrayersSection(person),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header (avatar + name) ──

  Widget _buildHeader(PersonModel person) {
    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            child: Text(
              person.initials,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_editingField == 'name')
            SizedBox(
              width: 250,
              child: TextField(
                controller: _nameController,
                focusNode: _nameFocus,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.words,
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onSubmitted: (_) => _saveField('name'),
              ),
            )
          else
            GestureDetector(
              onTap: () => _startEditing('name', _nameFocus),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    person.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 16, color: Colors.grey.shade400),
                ],
              ),
            ),
          if (person.relation.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              person.relation,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ],
      ),
    );
  }

  // ── Relation chips ──

  Widget _buildRelationSection(PersonModel person) {
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
            final isSelected = person.relation == relation;
            return ChoiceChip(
              label: Text(relation),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  FocusScope.of(context).unfocus();
                  if (_editingField != null) _saveField(_editingField!);
                  _saveRelation(relation);
                }
              },
              selectedColor: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.15),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.25)
                      : Theme.of(context)
                          .primaryColor
                          .withValues(alpha: 0.15),
                  width: 1.0,
                ),
              ),
              labelStyle: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Generic editable field ──

  Widget _buildEditableField({
    required String field,
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    final isEditing = _editingField == field;
    final hasValue = controller.text.trim().isNotEmpty;

    return GestureDetector(
      onTap: () => _startEditing(field, focusNode),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isEditing ? Colors.white : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: isEditing
              ? Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.3),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey.shade500),
            const SizedBox(width: 12),
            Expanded(
              child: isEditing
                  ? TextField(
                      controller: controller,
                      focusNode: focusNode,
                      keyboardType: keyboardType,
                      textCapitalization: capitalization,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: label,
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade400,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saveField(field),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasValue ? controller.text : 'Tap to add',
                          style: TextStyle(
                            fontSize: 15,
                            color: hasValue
                                ? Colors.grey.shade800
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
            ),
            if (isEditing)
              IconButton(
                icon: const Icon(Icons.check, size: 20),
                onPressed: () => _saveField(field),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: AppTheme.teal,
              )
            else
              Icon(Icons.edit, size: 14, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // ── Notes section ──

  Widget _buildNotesSection(PersonModel person) {
    final isEditing = _editingField == 'notes';
    final hasNotes = _notesController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Notes',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const Spacer(),
            if (!isEditing)
              GestureDetector(
                onTap: () => _startEditing('notes', _notesFocus),
                child: Icon(Icons.edit, size: 16, color: Colors.grey.shade400),
              ),
            if (isEditing)
              GestureDetector(
                onTap: () => _saveField('notes'),
                child: const Icon(Icons.check,
                    size: 20, color: AppTheme.teal),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: isEditing ? null : () => _startEditing('notes', _notesFocus),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isEditing ? Colors.white : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: isEditing
                  ? Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.3),
                    )
                  : null,
            ),
            child: isEditing
                ? TextField(
                    controller: _notesController,
                    focusNode: _notesFocus,
                    maxLines: null,
                    minLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 15, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Add notes about this person...',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade400,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  )
                : Text(
                    hasNotes ? _notesController.text : 'Tap to add notes...',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: hasNotes
                          ? Colors.grey.shade800
                          : Colors.grey.shade400,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Linked prayers section ──

  Widget _buildLinkedPrayersSection(PersonModel person) {
    final prayersAsync = ref.watch(prayersStreamProvider);

    return prayersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (prayers) {
        // Find prayers that have this person's ID in their metadata
        final linkedPrayers = prayers.where((p) {
          final cat = p.category;
          if (cat == null) return false;
          return cat.contains(person.id);
        }).toList();

        if (linkedPrayers.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Linked Prayers',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            ...linkedPrayers.map((prayer) => InkWell(
                  onTap: () =>
                      Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PrayerDetailScreen(prayerId: prayer.id),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.brandPurple.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            AppTheme.brandPurple.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.favorite_outline,
                            size: 18, color: AppTheme.brandPurple),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            prayer.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}
