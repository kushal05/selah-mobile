import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../domain/models/prayer_metadata_codec.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/selectable_chip.dart';

/// Screen for adding a new prayer
/// Provides form fields for title, description, status, reminder, and tags
class AddPrayerScreen extends ConsumerStatefulWidget {
  const AddPrayerScreen({super.key});

  @override
  ConsumerState<AddPrayerScreen> createState() => _AddPrayerScreenState();
}

class _AddPrayerScreenState extends ConsumerState<AddPrayerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _status = 'Active';
  DateTime? _reminderDate;
  TimeOfDay? _reminderTime;
  String? _recurrence; // null, 'Daily', or 'Weekly'
  final List<String> _tags = [];
  final List<String> _linkedPeopleIds = [];
  bool _isAddingTag = false;
  final _tagController = TextEditingController();
  final _tagInputFocusNode = FocusNode();

  static const _bulletPrefix = '• ';
  static const _checkboxUnchecked = '☐ ';
  static const _checkboxChecked = '☑ ';
  static const _allPrefixes = [_bulletPrefix, _checkboxUnchecked, _checkboxChecked];
  static final _numberedCaptureRegex = RegExp(r'^(\d+)\. (.*)$');

  ({String text, int cursorPos, int lineStart, int lineEnd, String line}) _currentLineInfo() {
    final text = _descriptionController.text;
    final sel = _descriptionController.selection;
    final cursorPos = sel.isValid ? sel.baseOffset : text.length;
    int lineStart = text.lastIndexOf('\n', cursorPos - 1);
    lineStart = lineStart == -1 ? 0 : lineStart + 1;
    int lineEnd = text.indexOf('\n', cursorPos);
    if (lineEnd == -1) lineEnd = text.length;
    return (text: text, cursorPos: cursorPos, lineStart: lineStart, lineEnd: lineEnd, line: text.substring(lineStart, lineEnd));
  }

  void _toggleLineFormat(String prefix) {
    final (:text, :cursorPos, :lineStart, :lineEnd, :line) = _currentLineInfo();

    final numberedMatch = _numberedCaptureRegex.firstMatch(line);
    final existingNumbered = numberedMatch == null ? null : '${numberedMatch.group(1)}. ';

    String newLine;
    int cursorDelta;

    if (line.startsWith(prefix)) {
      newLine = line.substring(prefix.length);
      cursorDelta = -prefix.length;
    } else {
      String stripped = line;
      int removedLen = 0;
      if (existingNumbered != null && prefix != existingNumbered) {
        stripped = line.substring(existingNumbered.length);
        removedLen = existingNumbered.length;
      } else {
        for (final p in _allPrefixes) {
          if (line.startsWith(p) && p != prefix) {
            stripped = line.substring(p.length);
            removedLen = p.length;
            break;
          }
        }
      }
      newLine = prefix + stripped;
      cursorDelta = prefix.length - removedLen;
    }

    final newText = text.substring(0, lineStart) + newLine + text.substring(lineEnd);
    final newCursor = (cursorPos + cursorDelta).clamp(lineStart, lineStart + newLine.length);

    _descriptionController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }

  int _nextNumberedListIndex() {
    final (:text, :lineStart, cursorPos: _, lineEnd: _, line: _) = _currentLineInfo();

    int count = 1;
    int prev = lineStart - 1;
    while (prev > 0) {
      int prevLineStart = text.lastIndexOf('\n', prev - 1);
      prevLineStart = prevLineStart == -1 ? 0 : prevLineStart + 1;
      final prevLine = text.substring(prevLineStart, prev);
      if (_numberedCaptureRegex.hasMatch(prevLine)) {
        count++;
        prev = prevLineStart - 1;
      } else {
        break;
      }
    }
    return count;
  }

  void _applyNumberedList() {
    final (line: line, cursorPos: _, text: _, lineStart: _, lineEnd: _) = _currentLineInfo();
    final m = _numberedCaptureRegex.firstMatch(line);
    _toggleLineFormat(m != null ? '${m.group(1)}. ' : '${_nextNumberedListIndex()}. ');
  }

  Widget _buildFormattingToolbar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.hairline),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 6),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _FormatButton(
            icon: Icons.format_list_bulleted,
            tooltip: l10n(context).bulletList,
            onTap: () => _toggleLineFormat(_bulletPrefix),
          ),
          _FormatButton(
            icon: Icons.format_list_numbered,
            tooltip: l10n(context).numberedList,
            onTap: _applyNumberedList,
          ),
          _FormatButton(
            icon: Icons.check_box_outline_blank,
            tooltip: l10n(context).checkbox,
            onTap: () => _toggleLineFormat(_checkboxUnchecked),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
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
          tooltip: l10n(context).close,
          icon: const Icon(Icons.close),
          onPressed: () => _handleClose(context),
        ),
        title: Text(l10n(context).newPrayer),
        actions: [
          TextButton(
            onPressed: _handleSave,
            child: Text(l10n(context).actionSave),
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
                // Title field
                _buildTitleField(),
                const SizedBox(height: 24),

                // Description field
                _buildDescriptionField(),
                const SizedBox(height: 24),

                // Status selector
                _buildStatusSelector(),
                const SizedBox(height: 24),

                // Reminder section
                _buildReminderSection(),
                const SizedBox(height: 24),

                // Recurring section
                _buildRecurringSection(),
                const SizedBox(height: 24),

                // Tags section
                _buildTagsSection(),
                const SizedBox(height: 24),

                // Linked People section (placeholder for future)
                _buildLinkedPeopleSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: l10n(context).title,
        hintText: l10n(context).whatWouldYouLikeToPrayFor,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        prefixIcon: Icon(Icons.edit_outlined, color: context.hintText),
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
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        labelStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        hintStyle: TextStyle(
          fontSize: 16,
          color: context.hintText,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a title';
        }
        return null;
      },
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      decoration: BoxDecoration(
        color: context.subtleFill,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n(context).description,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildFormattingToolbar(),
          TextField(
            controller: _descriptionController,
            decoration: AppTheme.inlineInput(hint: l10n(context).shareTheDetailsOfYourPrayerRequest),
            maxLines: null,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n(context).status,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['Active', 'Answered', 'Archived'].map((status) {
            final isSelected = _status == status;
            return ChoiceChip(
              label: Text(status),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  FocusScope.of(context).unfocus();
                  setState(() => _status = status);
                }
              },
              selectedColor: _getStatusColor(status).withValues(alpha: 0.15),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? _getStatusColor(status).withValues(alpha: 0.25)
                      : Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  width: 1.0,
                ),
              ),
              labelStyle: TextStyle(
                color: isSelected ? _getStatusColor(status) : Colors.grey.shade700,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return AppTheme.brandBlue;
      case 'Answered':
        return AppTheme.teal;
      case 'Archived':
        return AppTheme.mutedGrey;
      default:
        return Theme.of(context).primaryColor;
    }
  }

  Widget _buildReminderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n(context).reminder,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildReminderButton(
                icon: Icons.calendar_today,
                label: _reminderDate != null
                    ? _formatDate(_reminderDate!)
                    : 'Set date',
                onTap: _selectDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildReminderButton(
                icon: Icons.access_time,
                label: _reminderTime != null
                    ? _formatTime(_reminderTime!)
                    : 'Set time',
                onTap: _selectTime,
              ),
            ),
          ],
        ),
        if (_reminderDate != null || _reminderTime != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: () {
                FocusScope.of(context).unfocus();
                setState(() {
                  _reminderDate = null;
                  _reminderTime = null;
                });
              },
              icon: const Icon(Icons.clear, size: 16),
              label: Text(l10n(context).clearReminder),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecurringSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n(context).recurring,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n(context).none),
              selected: _recurrence == null,
              onSelected: (selected) {
                if (selected) {
                  FocusScope.of(context).unfocus();
                  setState(() => _recurrence = null);
                }
              },
              selectedColor: Colors.grey.shade200,
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _recurrence == null
                      ? Colors.grey.shade500.withValues(alpha: 0.25)
                      : Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  width: 1.0,
                ),
              ),
              labelStyle: TextStyle(
                color: _recurrence == null ? Colors.grey.shade800 : Colors.grey.shade600,
                fontWeight: _recurrence == null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            ChoiceChip(
              label: Text(l10n(context).daily),
              selected: _recurrence == 'Daily',
              onSelected: (selected) {
                if (selected) {
                  FocusScope.of(context).unfocus();
                  setState(() => _recurrence = 'Daily');
                }
              },
              selectedColor: AppTheme.brandBlue.withValues(alpha: 0.15),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _recurrence == 'Daily'
                      ? AppTheme.brandBlue.withValues(alpha: 0.25)
                      : Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  width: 1.0,
                ),
              ),
              labelStyle: TextStyle(
                color: _recurrence == 'Daily' ? AppTheme.brandBlue : Colors.grey.shade600,
                fontWeight: _recurrence == 'Daily' ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            ChoiceChip(
              label: Text(l10n(context).weekly),
              selected: _recurrence == 'Weekly',
              onSelected: (selected) {
                if (selected) {
                  FocusScope.of(context).unfocus();
                  setState(() => _recurrence = 'Weekly');
                }
              },
              selectedColor: AppTheme.brandPurple.withValues(alpha: 0.15),
              backgroundColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _recurrence == 'Weekly'
                      ? AppTheme.brandPurple.withValues(alpha: 0.25)
                      : Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  width: 1.0,
                ),
              ),
              labelStyle: TextStyle(
                color: _recurrence == 'Weekly' ? AppTheme.brandPurple : Colors.grey.shade600,
                fontWeight: _recurrence == 'Weekly' ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReminderButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final bool hasValue = !label.startsWith('Set');
    return Material(
      color: context.subtleFill,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasValue
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                      : context.subtleFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: hasValue
                      ? Theme.of(context).primaryColor
                      : context.mutedText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: hasValue ? FontWeight.w500 : FontWeight.normal,
                    color: hasValue ? Colors.grey.shade800 : Colors.grey.shade500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasValue)
                Icon(Icons.check_circle, size: 18, color: Theme.of(context).primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n(context).tags,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._tags.map((tag) => SelectableChip(
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
              color: context.subtleFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    focusNode: _tagInputFocusNode,
                    decoration: InputDecoration(
                      hintText: l10n(context).enterTagName,
                      prefixIcon: Icon(Icons.label_outline, size: 20, color: context.hintText),
                      filled: true,
                      fillColor: Colors.transparent,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintStyle: TextStyle(
                        fontSize: 16,
                        color: context.hintText,
                      ),
                    ),
                    style: const TextStyle(fontSize: 16),
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: _submitTag,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l10n(context).addTag,
                  icon: Icon(
                    Icons.check,
                    color: Theme.of(context).primaryColor,
                  ),
                  onPressed: () => _submitTag(_tagController.text),
                ),
                IconButton(
                  tooltip: l10n(context).actionCancel,
                  icon: Icon(
                    Icons.close,
                    color: context.mutedText,
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
            label: Text(l10n(context).addTag),
          ),
      ],
    );
  }

  Widget _buildLinkedPeopleSection() {
    final peopleAsync = ref.watch(peopleStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n(context).linkedPeople,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        peopleAsync.when(
          loading: () => const Column(children: [ListTileSkeleton(), ListTileSkeleton()]),
          error: (error, _) => Text(UserFacingError.forLoad(error)),
          data: (people) {
            if (people.isEmpty && _linkedPeopleIds.isEmpty) {
              return _buildEmptyPeoplePrompt();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selected people chips
                if (_linkedPeopleIds.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _linkedPeopleIds.map((id) {
                      final person = people.where((p) => p.id == id).firstOrNull;
                      final name = person?.name ?? 'Unknown';
                      return SelectableChip(
                        label: name,
                        isSelected: true,
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _linkedPeopleIds.remove(id));
                        },
                        showDelete: true,
                        icon: Icons.person,
                      );
                    }).toList(),
                  ),
                if (_linkedPeopleIds.isNotEmpty)
                  const SizedBox(height: 12),
                // Available people to select
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: people
                      .where((p) => !_linkedPeopleIds.contains(p.id))
                      .map((person) => SelectableChip(
                            label: person.name,
                            isSelected: false,
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              setState(() => _linkedPeopleIds.add(person.id));
                            },
                            icon: Icons.person_outline,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                _buildAddPersonButton(),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyPeoplePrompt() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 32, color: context.hintText),
          const SizedBox(height: 8),
          Text(
            l10n(context).noPeopleAddedYet,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n(context).addAPersonToLinkToThisPrayer,
            style: TextStyle(
              fontSize: 14,
              color: context.mutedText,
            ),
          ),
          const SizedBox(height: 12),
          _buildAddPersonButton(),
        ],
      ),
    );
  }

  Widget _buildAddPersonButton() {
    return TextButton.icon(
      onPressed: _showAddPersonDialog,
      icon: const Icon(Icons.person_add, size: 18),
      label: Text(l10n(context).addPerson),
    );
  }

  Future<void> _showAddPersonDialog() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n(context).addPerson),
          content: TextField(
            controller: nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l10n(context).name,
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
              child: Text(l10n(context).actionCancel),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(context).pop(name);
                }
              },
              child: Text(l10n(context).add),
            ),
          ],
        );
      },
    );
    nameController.dispose();

    if (result != null && mounted) {
      final repository = ref.read(personRepositoryProvider);
      final userId = ref.read(currentUserIdProvider);
      final person = await repository.createPerson(userId: userId, name: result);
      setState(() => _linkedPeopleIds.add(person.id));
    }
  }

  void _submitTag(String tag) {
    final trimmed = tag.trim();
    // Unfocus before removing the text field to prevent focus jumping
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

  Future<void> _selectDate() async {
    FocusScope.of(context).unfocus();
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) {
      setState(() => _reminderDate = date);
    }
  }

  Future<void> _selectTime() async {
    FocusScope.of(context).unfocus();
    final time = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? TimeOfDay.now(),
    );
    if (time != null) {
      setState(() => _reminderTime = time);
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  void _handleClose(BuildContext context) {
    if (_titleController.text.isNotEmpty ||
        _descriptionController.text.isNotEmpty ||
        _tags.isNotEmpty ||
        _linkedPeopleIds.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n(context).discardChanges),
          content: Text(l10n(context).youHaveUnsavedChangesAreYouSureYouWantToDisc),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n(context).actionCancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.pop();
              },
              child: Text(l10n(context).discard),
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
        final repository = ref.read(prayerRepositoryProvider);
        final userId = ref.read(currentUserIdProvider);

        // Map recurrence string to PrayerFrequency enum
        final frequency = _mapRecurrenceToFrequency(_recurrence);

        // Map status string to PrayerStatus enum
        final status = _mapStatusToEnum(_status);

        // Create the prayer
        final prayer = await repository.createPrayer(
          userId: userId,
          title: _titleController.text.trim(),
          content: _descriptionController.text.trim(),
          frequency: frequency,
          category: _buildMetadataField() ?? '',
          reminderAt: _buildReminderDateTime()?.millisecondsSinceEpoch,
        );

        // If status is not active, update it
        if (status != PrayerStatus.active) {
          if (status == PrayerStatus.answered) {
            await repository.markAsAnswered(prayer.id);
          } else if (status == PrayerStatus.archived) {
            await repository.archivePrayer(prayer.id);
          }
        }

        // Schedule reminder for active prayers
        if (status == PrayerStatus.active) {
          try {
            final reminderService = ref.read(prayerReminderServiceProvider);
            await reminderService.schedulePrayerReminderAt(
              prayer,
              preferredTime: _buildReminderDateTime(),
            );
          } catch (_) {
            // Non-critical: don't fail save if reminder scheduling fails
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n(context).prayerSavedSuccessfully),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(UserFacingError.message(e, action: 'save this prayer')),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.errorSurface,
            ),
          );
        }
      }
    }
  }

  String? _buildMetadataField() {
    if (_tags.isEmpty && _linkedPeopleIds.isEmpty) {
      return null;
    }
    return encodePrayerMetadata(
      PrayerMetadata(
        tags: List<String>.from(_tags),
        linkedPeopleIds: List<String>.from(_linkedPeopleIds),
      ),
    );
  }

  DateTime? _buildReminderDateTime() {
    if (_reminderDate == null && _reminderTime == null) return null;
    final now = DateTime.now();
    final date = _reminderDate ?? now;
    final time = _reminderTime ?? const TimeOfDay(hour: 8, minute: 0);
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  PrayerFrequency _mapRecurrenceToFrequency(String? recurrence) {
    switch (recurrence) {
      case 'Daily':
        return PrayerFrequency.daily;
      case 'Weekly':
        return PrayerFrequency.weekly;
      default:
        return PrayerFrequency.asNeeded;
    }
  }

  PrayerStatus _mapStatusToEnum(String status) {
    switch (status) {
      case 'Answered':
        return PrayerStatus.answered;
      case 'Archived':
        return PrayerStatus.archived;
      default:
        return PrayerStatus.active;
    }
  }
}

class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _FormatButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

