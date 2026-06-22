import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/models/promise_condition_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bible/presentation/providers/bible_providers.dart';
import '../../../bible/domain/models/bible_books.dart';
import '../../../notes/presentation/widgets/editor/bible_reference_picker.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../domain/models/promise_conditions_codec.dart';

/// Screen for adding or editing a promise
/// Provides form fields for verse reference, promise text, notes, tags, and conditions
class AddPromiseScreen extends ConsumerStatefulWidget {
  final String? promiseId;

  const AddPromiseScreen({super.key, this.promiseId});

  bool get isEditing => promiseId != null;

  @override
  ConsumerState<AddPromiseScreen> createState() => _AddPromiseScreenState();
}

class _AddPromiseScreenState extends ConsumerState<AddPromiseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _verseController = TextEditingController();
  final _promiseTextController = TextEditingController();
  final _notesController = TextEditingController();

  List<String> _tagIds = [];
  final List<PromiseConditionItem> _conditions = [];
  bool _isAddingTag = false;
  bool _isAddingCondition = false;
  final _tagController = TextEditingController();
  final _conditionController = TextEditingController();
  final _conditionNotesController = TextEditingController();
  String _conditionStatus = 'ACTIVE';
  final _tagInputFocusNode = FocusNode();
  final _conditionInputFocusNode = FocusNode();
  bool _isLoadingExisting = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _isLoadingExisting = true;
      _loadExistingPromise();
    }
  }

  Future<void> _loadExistingPromise() async {
    final repository = ref.read(promiseRepositoryProvider);
    final promise = await repository.getPromiseById(widget.promiseId!);
    if (mounted && promise != null) {
      // Load tags from junction table
      final promiseTagRepo = ref.read(promiseTagRepositoryProvider);
      final tagIds =
          await promiseTagRepo.getTagIdsForPromise(widget.promiseId!);

      // Load conditions from dedicated table
      final conditionRepo = ref.read(promiseConditionRepositoryProvider);
      final dbConditions =
          await conditionRepo.getConditionsForPromise(widget.promiseId!);

      setState(() {
        _verseController.text = promise.reference;
        _promiseTextController.text = promise.content;
        _notesController.text = promise.notes;
        _tagIds = tagIds;
        _conditions.addAll(dbConditions.map((c) => PromiseConditionItem(
              id: c.id,
              description: c.description,
              notes: c.notes.isEmpty ? null : c.notes,
              status: c.status.toDbValue(),
            )));
        _isLoadingExisting = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingExisting = false);
    }
  }

  @override
  void dispose() {
    _verseController.dispose();
    _promiseTextController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    _conditionController.dispose();
    _conditionNotesController.dispose();
    _tagInputFocusNode.dispose();
    _conditionInputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingExisting) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        body: const FormSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _handleClose(context),
        ),
        title: Text(widget.isEditing ? 'Edit Promise' : 'New Promise'),
        actions: [
          TextButton(
            onPressed: _handleSave,
            style: TextButton.styleFrom(foregroundColor: AppTheme.rosePink),
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: AppTheme.paddingAllBase,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVerseField(),
                const SizedBox(height: AppTheme.spacing24),
                _buildPromiseTextField(),
                const SizedBox(height: AppTheme.spacing24),
                _buildNotesField(),
                const SizedBox(height: AppTheme.spacing24),
                _buildTagsSection(),
                const SizedBox(height: AppTheme.spacing24),
                _buildConditionsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerseField() {
    final hasReference = _verseController.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verse Reference',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.gray700,
          ),
        ),
        const SizedBox(height: AppTheme.spacing8),
        InkWell(
          onTap: _openVersePicker,
          borderRadius: AppTheme.borderRadius3XL,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: AppTheme.spacing16),
            decoration: BoxDecoration(
              color: AppTheme.gray50,
              borderRadius: AppTheme.borderRadius3XL,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.book_outlined,
                  color: hasReference
                      ? AppTheme.rosePink
                      : AppTheme.gray400,
                ),
                const SizedBox(width: AppTheme.spacing12),
                Expanded(
                  child: Text(
                    hasReference
                        ? _verseController.text
                        : 'Tap to select a verse...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          hasReference ? FontWeight.w500 : FontWeight.normal,
                      color: hasReference
                          ? Colors.black87
                          : AppTheme.gray400,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: AppTheme.gray400,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openVersePicker() async {
    final selection = await BibleReferencePicker.show(
      context,
    );
    if (selection == null || !mounted) return;

    setState(() {
      _verseController.text = selection.displayReference;
    });

    _fetchVerseText(selection);
  }

  void _fetchVerseText(BibleReferenceSelection selection) {
    final bookIndex = BibleBooks.books.indexWhere(
      (b) => b.name == selection.book.name,
    );
    if (bookIndex < 0) return;

    final bookId = bookIndex + 1;
    final repo = ref.read(bibleRepositoryProvider);

    if (selection.verseEnd != null &&
        selection.verseEnd != selection.verseStart) {
      final verses = repo.getVerseRange(
        bookId: bookId,
        chapter: selection.chapter,
        verseStart: selection.verseStart,
        verseEnd: selection.verseEnd!,
        translation: selection.version,
      );
      if (verses.isNotEmpty) {
        setState(() {
          _promiseTextController.text = verses.map((v) => v.text).join(' ');
        });
      }
    } else {
      final verse = repo.getVerse(
        bookId: bookId,
        chapter: selection.chapter,
        verse: selection.verseStart,
        translation: selection.version,
      );
      if (verse != null) {
        setState(() {
          _promiseTextController.text = verse.text;
        });
      }
    }
  }

  Widget _buildPromiseTextField() {
    return TextFormField(
      controller: _promiseTextController,
      decoration: InputDecoration(
        labelText: 'Promise Text',
        hintText: 'Enter the promise verse or text...',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        alignLabelWithHint: true,
        filled: true,
        fillColor: AppTheme.gray50,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(bottom: 64),
          child: Icon(Icons.format_quote_outlined, color: AppTheme.gray400),
        ),
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
              color: AppTheme.rosePink.withValues(alpha: 0.3),
              width: 1.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppTheme.borderRadius3XL,
          borderSide: BorderSide(
              color: AppTheme.rosePink.withValues(alpha: 0.3),
              width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppTheme.borderRadius3XL,
          borderSide: BorderSide(
              color: AppTheme.rosePink.withValues(alpha: 0.3),
              width: 1.0),
        ),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTheme.gray700,
        ),
        hintStyle: TextStyle(
          fontSize: 15,
          color: AppTheme.gray400,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: AppTheme.spacing16),
      ),
      maxLines: 5,
      minLines: 3,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(
        fontSize: 15,
        height: 1.5,
        fontStyle: FontStyle.italic,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter the promise text';
        }
        return null;
      },
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      decoration: InputDecoration(
        labelText: 'Notes (Optional)',
        hintText: 'Add your reflections or explanation...',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        alignLabelWithHint: true,
        filled: true,
        fillColor: AppTheme.gray50,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(bottom: 64),
          child: Icon(Icons.notes_outlined, color: AppTheme.gray400),
        ),
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
              color: AppTheme.rosePink.withValues(alpha: 0.3),
              width: 1.0),
        ),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppTheme.gray700,
        ),
        hintStyle: TextStyle(
          fontSize: 15,
          color: AppTheme.gray400,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: AppTheme.spacing16),
      ),
      maxLines: 4,
      minLines: 2,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.newline,
      style: const TextStyle(
        fontSize: 15,
        height: 1.5,
      ),
    );
  }

  Widget _buildTagsSection() {
    final allTagsAsync = ref.watch(tagsStreamProvider);
    final userId = ref.read(currentUserIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.gray700,
          ),
        ),
        const SizedBox(height: AppTheme.spacing8),
        allTagsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (allTags) {
            return Wrap(
              spacing: AppTheme.spacing8,
              runSpacing: AppTheme.spacing8,
              children: allTags.map((tag) {
                final isSelected = _tagIds.contains(tag.id);
                return _SelectableChip(
                  label: tag.name,
                  isSelected: isSelected,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      if (isSelected) {
                        _tagIds.remove(tag.id);
                      } else {
                        _tagIds.add(tag.id);
                      }
                    });
                  },
                  showDelete: isSelected,
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: AppTheme.spacing12),
        if (_isAddingTag)
          Container(
            decoration: BoxDecoration(
              color: AppTheme.gray50,
              borderRadius: AppTheme.borderRadiusXL,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    focusNode: _tagInputFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Enter tag name...',
                      prefixIcon: Icon(Icons.label_outline,
                          size: AppTheme.iconBase, color: AppTheme.gray400),
                      filled: true,
                      fillColor: Colors.transparent,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing12, vertical: AppTheme.spacing14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: AppTheme.gray400,
                      ),
                    ),
                    style: const TextStyle(fontSize: 14),
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (name) => _submitTag(name, userId),
                  ),
                ),
                const SizedBox(width: AppTheme.spacing8),
                IconButton(
                  icon: Icon(
                    Icons.check,
                    color: AppTheme.rosePink,
                  ),
                  onPressed: () => _submitTag(_tagController.text, userId),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppTheme.gray500,
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
            style: TextButton.styleFrom(foregroundColor: AppTheme.rosePink),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add tag'),
          ),
      ],
    );
  }

  Widget _buildConditionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Conditions',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.gray700,
          ),
        ),
        const SizedBox(height: AppTheme.spacing8),
        ..._conditions.map((condition) => _buildConditionCard(condition)),
        const SizedBox(height: AppTheme.spacing12),
        if (_isAddingCondition)
          _buildConditionForm()
        else
          TextButton.icon(
            onPressed: () {
              setState(() => _isAddingCondition = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _conditionInputFocusNode.requestFocus();
              });
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.rosePink),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add condition'),
          ),
      ],
    );
  }

  Widget _buildConditionCard(PromiseConditionItem condition) {
    final isMet = condition.status.toUpperCase() == 'MET';
    final isActive = condition.status.toUpperCase() == 'ACTIVE';

    Color statusColor;
    if (isMet) {
      statusColor = Colors.green;
    } else if (isActive) {
      statusColor = AppTheme.rosePink;
    } else {
      statusColor = AppTheme.promiseInactive;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing12),
      padding: AppTheme.paddingAllBase,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.borderRadiusXL,
        border: Border.all(color: AppTheme.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isMet ? Icons.check_circle : Icons.radio_button_unchecked,
                color: statusColor,
                size: AppTheme.iconBase,
              ),
              const SizedBox(width: AppTheme.spacing12),
              Expanded(
                child: Text(
                  condition.description,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppTheme.spacing12, vertical: AppTheme.spacing4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: AppTheme.alphaLightMed),
                  borderRadius: AppTheme.borderRadiusMD,
                ),
                child: Text(
                  condition.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacing8),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: AppTheme.gray500),
                onPressed: () {
                  setState(() => _conditions.remove(condition));
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (condition.notes != null && condition.notes!.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing8),
            Text(
              condition.notes!,
              style: TextStyle(fontSize: 14, color: AppTheme.gray600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConditionForm() {
    return Container(
      padding: AppTheme.paddingAllBase,
      decoration: BoxDecoration(
        color: AppTheme.gray50,
        borderRadius: AppTheme.borderRadiusXL,
        border: Border.all(color: AppTheme.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _conditionController,
            focusNode: _conditionInputFocusNode,
            decoration: InputDecoration(
              hintText: 'Enter condition description...',
              prefixIcon: Icon(Icons.check_circle_outline,
                  size: AppTheme.iconBase, color: AppTheme.gray400),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppTheme.spacing12, vertical: AppTheme.spacing14),
              border: OutlineInputBorder(
                borderRadius: AppTheme.borderRadiusXL,
                borderSide: BorderSide.none,
              ),
              hintStyle: TextStyle(fontSize: 14, color: AppTheme.gray400),
            ),
            style: const TextStyle(fontSize: 14),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppTheme.spacing12),
          TextField(
            controller: _conditionNotesController,
            decoration: InputDecoration(
              hintText: 'Notes (optional)...',
              prefixIcon: Icon(Icons.notes_outlined,
                  size: AppTheme.iconBase, color: AppTheme.gray400),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: AppTheme.spacing12, vertical: AppTheme.spacing14),
              border: OutlineInputBorder(
                borderRadius: AppTheme.borderRadiusXL,
                borderSide: BorderSide.none,
              ),
              hintStyle: TextStyle(fontSize: 14, color: AppTheme.gray400),
            ),
            style: const TextStyle(fontSize: 14),
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
          ),
          const SizedBox(height: AppTheme.spacing12),
          Text(
            'Status',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.gray600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Wrap(
            spacing: AppTheme.spacing8,
            children: ['ACTIVE', 'MET', 'NOT_MET'].map((status) {
              final isSelected = _conditionStatus == status;
              return ChoiceChip(
                label: Text(status),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    FocusScope.of(context).unfocus();
                    setState(() => _conditionStatus = status);
                  }
                },
                selectedColor:
                    _getConditionStatusColor(status).withValues(alpha: AppTheme.alphaMedium),
                backgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: AppTheme.borderRadius4XL,
                  side: BorderSide(
                    color: isSelected
                        ? _getConditionStatusColor(status)
                            .withValues(alpha: 0.25)
                        : Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.15),
                    width: 1.0,
                  ),
                ),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? _getConditionStatusColor(status)
                      : AppTheme.gray700,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppTheme.spacing16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _isAddingCondition = false;
                    _conditionController.clear();
                    _conditionNotesController.clear();
                    _conditionStatus = 'ACTIVE';
                  });
                },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppTheme.spacing8),
              FilledButton(
                onPressed: _submitCondition,
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getConditionStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'MET':
        return Colors.green;
      case 'ACTIVE':
        return AppTheme.rosePink;
      case 'NOT_MET':
        return AppTheme.promiseInactive;
      default:
        return AppTheme.gray500;
    }
  }

  Future<void> _submitTag(String name, String userId) async {
    final trimmed = name.trim();
    FocusScope.of(context).unfocus();
    if (trimmed.isNotEmpty) {
      final tagRepo = ref.read(tagRepositoryProvider);
      final tag = await tagRepo.getOrCreateTag(trimmed, userId);
      if (mounted && !_tagIds.contains(tag.id)) {
        setState(() {
          _tagIds.add(tag.id);
          _tagController.clear();
          _isAddingTag = false;
        });
      } else if (mounted) {
        setState(() {
          _tagController.clear();
          _isAddingTag = false;
        });
      }
    } else {
      setState(() {
        _tagController.clear();
        _isAddingTag = false;
      });
    }
  }

  void _submitCondition() {
    final description = _conditionController.text.trim();
    if (description.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _conditions.add(PromiseConditionItem(
        description: description,
        notes: _conditionNotesController.text.trim().isEmpty
            ? null
            : _conditionNotesController.text.trim(),
        status: _conditionStatus,
      ));
      _conditionController.clear();
      _conditionNotesController.clear();
      _conditionStatus = 'ACTIVE';
      _isAddingCondition = false;
    });
  }

  void _handleClose(BuildContext context) {
    if (_verseController.text.isNotEmpty ||
        _promiseTextController.text.isNotEmpty ||
        _notesController.text.isNotEmpty ||
        _tagIds.isNotEmpty ||
        _conditions.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
              'You have unsaved changes. Are you sure you want to discard them?'),
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
        final repository = ref.read(promiseRepositoryProvider);
        final userId = ref.read(currentUserIdProvider);
        final promiseTagRepo = ref.read(promiseTagRepositoryProvider);
        final conditionRepo = ref.read(promiseConditionRepositoryProvider);

        String promiseId;

        if (widget.isEditing) {
          promiseId = widget.promiseId!;
          await repository.updatePromise(
            id: promiseId,
            reference: _verseController.text.trim(),
            content: _promiseTextController.text.trim(),
            notes: _notesController.text.trim(),
          );
        } else {
          final created = await repository.createPromise(
            userId: userId,
            reference: _verseController.text.trim(),
            content: _promiseTextController.text.trim(),
            notes: _notesController.text.trim(),
          );
          promiseId = created.id;
        }

        // Save tags via junction table
        await promiseTagRepo.setTagsForPromise(promiseId, _tagIds, userId);

        // Save conditions via dedicated table
        await _saveConditions(conditionRepo, promiseId, userId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.isEditing
                  ? 'Promise updated successfully'
                  : 'Promise saved successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving promise: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _saveConditions(
    dynamic conditionRepo,
    String promiseId,
    String userId,
  ) async {
    if (widget.isEditing) {
      final existing =
          await conditionRepo.getConditionsForPromise(promiseId)
              as List<PromiseConditionModel>;
      final existingIds = existing.map((c) => c.id).toSet();
      final currentIds =
          _conditions.where((c) => c.id != null).map((c) => c.id!).toSet();

      // Delete removed conditions
      for (final id in existingIds.difference(currentIds)) {
        await conditionRepo.deleteCondition(id);
      }

      // Update existing conditions
      for (final item in _conditions.where((c) => c.id != null)) {
        await conditionRepo.updateCondition(
          id: item.id!,
          description: item.description,
          notes: item.notes ?? '',
          status: PromiseConditionStatus.fromDbValue(item.status),
        );
      }

      // Create new conditions
      for (final item in _conditions.where((c) => c.id == null)) {
        await conditionRepo.addCondition(
          promiseId: promiseId,
          userId: userId,
          description: item.description,
          notes: item.notes ?? '',
          status: PromiseConditionStatus.fromDbValue(item.status),
        );
      }
    } else {
      for (final item in _conditions) {
        await conditionRepo.addCondition(
          promiseId: promiseId,
          userId: userId,
          description: item.description,
          notes: item.notes ?? '',
          status: PromiseConditionStatus.fromDbValue(item.status),
        );
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
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.borderRadius3XL,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing12, vertical: AppTheme.spacing6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.rosePink : AppTheme.gray200,
          borderRadius: AppTheme.borderRadius3XL,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isSelected ? Colors.white : AppTheme.gray700,
              ),
            ),
            if (showDelete && isSelected) ...[
              const SizedBox(width: AppTheme.spacing4),
              Icon(
                Icons.close,
                size: AppTheme.iconMD,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
