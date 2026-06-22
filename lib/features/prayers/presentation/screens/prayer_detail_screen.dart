import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/group_model.dart';
import '../../../../core/sync/models/prayer_collaborator_model.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/models/prayer_update_model.dart';
import '../../../../core/sync/models/shared_prayer_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/sync/models/promise_model.dart';
import '../../../../shared/widgets/dialogs/link_picker_dialog.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../../../shared/widgets/timeline_item.dart';
import '../../domain/models/prayer_metadata_codec.dart';
import '../widgets/share_prayer_sheet.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

const _updatesSeparator = '\n<!-- updates -->\n';

/// Prayer detail screen showing prayer information and updates
class PrayerDetailScreen extends ConsumerStatefulWidget {
  final String prayerId;

  const PrayerDetailScreen({super.key, required this.prayerId});

  @override
  ConsumerState<PrayerDetailScreen> createState() => _PrayerDetailScreenState();
}

class _PrayerDetailScreenState extends ConsumerState<PrayerDetailScreen> {
  bool _isEditingTitle = false;
  bool _isEditingDescription = false;
  bool _controllersInitialized = false;

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  // Formatting prefixes used in description lines.
  static const _bulletPrefix = '• ';
  static const _checkboxUnchecked = '☐ ';
  static const _checkboxChecked = '☑ ';
  static const _allPrefixes = [_bulletPrefix, _checkboxUnchecked, _checkboxChecked];
  // Captures number + content (e.g. "1. text" → group(1)="1", group(2)="text").
  // Also used for plain hasMatch detection — covers all numbered-line uses.
  static final _numberedCaptureRegex = RegExp(r'^(\d+)\. (.*)$');

  // Cache for _buildDescriptionContent — avoids rebuilding on unrelated setStates.
  String? _cachedDescText;
  bool? _cachedCanEdit;
  Widget? _cachedDescWidget;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  /// Initialize controllers from prayer data on first load.
  void _initControllersFromPrayer(PrayerModel prayer) {
    if (_controllersInitialized) return;
    _controllersInitialized = true;
    _titleController.text = prayer.title;
    _descriptionController.text = _extractDescription(prayer.content);
  }

  /// Extract just the description portion, stripping any legacy embedded updates.
  String _extractDescription(String content) {
    final idx = content.indexOf(_updatesSeparator);
    if (idx == -1) return content;
    return content.substring(0, idx);
  }

  /// Parse legacy updates embedded in content (for migration display).
  List<Map<String, dynamic>> _parseLegacyUpdates(String content) {
    final idx = content.indexOf(_updatesSeparator);
    if (idx == -1) return [];
    final jsonStr = content.substring(idx + _updatesSeparator.length);
    try {
      return (jsonDecode(jsonStr) as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveTitle() async {
    final newTitle = _titleController.text.trim();
    setState(() => _isEditingTitle = false);

    final currentPrayer = ref.read(prayerByIdProvider(widget.prayerId)).valueOrNull;
    if (currentPrayer != null && newTitle != currentPrayer.title) {
      try {
        final repository = ref.read(prayerRepositoryProvider);
        await repository.updatePrayer(
          id: widget.prayerId,
          title: newTitle,
        );
        if (mounted) {
          ref.invalidate(prayerByIdProvider(widget.prayerId));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving: $e')),
          );
        }
      }
    }
  }

  /// Returns the text, cursor position, line bounds, and content of the line the cursor is on.
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

  /// Toggles a formatting prefix on the line where the cursor currently sits.
  /// Bullet: '• ', Numbered: '1. ', Checkbox: '☐ '.
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

  /// Toggles the checkbox state of a specific line, then saves.
  Future<void> _toggleCheckboxAtLine(int lineIndex, bool currentlyChecked) async {
    final lines = _descriptionController.text.split('\n');
    if (lineIndex >= lines.length) return;

    final line = lines[lineIndex];
    if (currentlyChecked) {
      lines[lineIndex] = _checkboxUnchecked + line.substring(_checkboxChecked.length);
    } else {
      lines[lineIndex] = _checkboxChecked + line.substring(_checkboxUnchecked.length);
    }

    // Preserve cursor position (view-mode tap, but defensive for future edit-mode use).
    final sel = _descriptionController.selection;
    final offset = sel.isValid ? sel.baseOffset : 0;
    final joined = lines.join('\n');
    _descriptionController.value = TextEditingValue(
      text: joined,
      selection: TextSelection.collapsed(offset: offset.clamp(0, joined.length)),
    );
    await _saveDescription();
  }

  /// Returns the next sequential number for a numbered list at the cursor position.
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
    // If the line is already numbered, pass its actual prefix so _toggleLineFormat
    // removes it. Using _nextNumberedListIndex() here would produce a different
    // number, causing a renumber instead of a toggle-off.
    _toggleLineFormat(m != null ? '${m.group(1)}. ' : '${_nextNumberedListIndex()}. ');
  }

  /// Renders the description text with visual formatting for bullets, numbered
  /// lists, and checkboxes. Result is cached to avoid rebuilding on unrelated setStates.
  Widget _buildDescriptionContent(String text, bool canEdit) {
    if (text == _cachedDescText && canEdit == _cachedCanEdit && _cachedDescWidget != null) {
      return _cachedDescWidget!;
    }
    _cachedDescText = text;
    _cachedCanEdit = canEdit;
    _cachedDescWidget = _buildDescriptionContentUncached(text, canEdit);
    return _cachedDescWidget!;
  }

  Widget _buildDescriptionContentUncached(String text, bool canEdit) {
    if (text.isEmpty) {
      return Text(
        'No description',
        style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
      );
    }

    final lines = text.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith(_checkboxUnchecked) || line.startsWith(_checkboxChecked)) {
        final isChecked = line.startsWith(_checkboxChecked);
        final content = line.substring(_checkboxUnchecked.length);
        widgets.add(
          GestureDetector(
            onTap: canEdit ? () => _toggleCheckboxAtLine(i, isChecked) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18,
                    color: isChecked ? AppTheme.teal : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      content,
                      style: TextStyle(
                        fontSize: 16,
                        decoration: isChecked ? TextDecoration.lineThrough : null,
                        color: isChecked ? Colors.grey.shade500 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else if (line.startsWith(_bulletPrefix)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line.substring(_bulletPrefix.length),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final numberedMatch = _numberedCaptureRegex.firstMatch(line);
        if (numberedMatch != null) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${numberedMatch.group(1)}.',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      numberedMatch.group(2)!,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                // ' ' instead of '' preserves blank-line height; Text('') collapses to zero.
                line.isEmpty ? ' ' : line,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          );
        }
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  /// Formatting toolbar shown when editing the description.
  Widget _buildFormattingToolbar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 6),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _FormatButton(
            icon: Icons.format_list_bulleted,
            tooltip: 'Bullet list',
            onTap: () => _toggleLineFormat(_bulletPrefix),
          ),
          _FormatButton(
            icon: Icons.format_list_numbered,
            tooltip: 'Numbered list',
            onTap: _applyNumberedList,
          ),
          _FormatButton(
            icon: Icons.check_box_outline_blank,
            tooltip: 'Checkbox',
            onTap: () => _toggleLineFormat(_checkboxUnchecked),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDescription() async {
    final currentPrayer = ref.read(prayerByIdProvider(widget.prayerId)).valueOrNull;
    if (currentPrayer == null) return;

    // Capture before the write so the catch block can revert without a second provider read.
    final currentDescription = _extractDescription(currentPrayer.content);
    final newDescription = _descriptionController.text.trim();

    // Sync controller to the trimmed value so subsequent saves don't see false dirty state.
    // Use .value to preserve cursor position in case the field is still in edit mode.
    if (_descriptionController.text != newDescription) {
      final sel = _descriptionController.selection;
      _descriptionController.value = TextEditingValue(
        text: newDescription,
        selection: TextSelection.collapsed(
          offset: sel.isValid
              ? sel.baseOffset.clamp(0, newDescription.length)
              : newDescription.length,
        ),
      );
    }
    if (_isEditingDescription) setState(() => _isEditingDescription = false);

    if (newDescription != currentDescription) {
      try {
        final repository = ref.read(prayerRepositoryProvider);
        await repository.updatePrayer(
          id: widget.prayerId,
          content: newDescription,
        );
        if (mounted) {
          ref.invalidate(prayerByIdProvider(widget.prayerId));
        }
      } catch (e) {
        // Revert to the pre-save description captured above.
        _descriptionController.text = currentDescription;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving: $e')),
          );
        }
      }
    }
  }

  Future<void> _cancelReminder() async {
    try {
      final reminderService = ref.read(prayerReminderServiceProvider);
      await reminderService.cancelPrayerReminder(widget.prayerId);
    } catch (_) {
      // Non-critical
    }
  }

  Future<void> _addUpdate(String text) async {
    try {
      final userId = ref.read(currentUserIdProvider);
      final updateRepo = ref.read(prayerUpdateRepositoryProvider);
      await updateRepo.addUpdate(
        prayerId: widget.prayerId,
        userId: userId,
        content: text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _todaySessionDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _logPrayer({String note = ''}) async {
    try {
      final userId = ref.read(currentUserIdProvider);
      final repo = ref.read(prayerLogRepositoryProvider);
      await repo.logPrayer(
        prayerId: widget.prayerId,
        userId: userId,
        note: note,
        sessionDate: _todaySessionDate(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prayer logged'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to log prayer: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showLogPrayerDialog() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Prayer'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Optional note',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Log'),
          ),
        ],
      ),
    );
    if (note != null) {
      await _logPrayer(note: note);
    }
  }

  Future<void> _showShareToGroupSheet(BuildContext context) async {
    final groupsAsync = ref.read(groupsListProvider);
    final groups = groupsAsync.valueOrNull ?? <GroupModel>[];

    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are not a member of any groups'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<GroupModel>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.group_add, color: AppTheme.brandBlue),
                    const SizedBox(width: 12),
                    Text(
                      'Share to Group',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...groups.map((group) => ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          AppTheme.brandBlue.withValues(alpha: 0.1),
                      child: Text(
                        group.initials,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brandBlue,
                        ),
                      ),
                    ),
                    title: Text(group.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, group),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected != null && context.mounted) {
      try {
        final api = ref.read(groupContentApiServiceProvider);
        await api.addGroupPrayer(
          groupId: selected.id,
          prayerId: widget.prayerId,
        );
        ref.invalidate(groupPrayersProvider(selected.id));

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Prayer shared to "${selected.name}"'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to share: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  _PrayerPermissions _computePermissions({
    required PrayerModel prayer,
    required String currentUserId,
    required SharedPrayerModel? sharedPrayer,
    required List<PrayerCollaboratorModel> collaborators,
  }) {
    final isOwner = prayer.userId == currentUserId;
    if (isOwner) {
      return const _PrayerPermissions(
        canEdit: true,
        canLog: true,
        canAddUpdates: true,
        canManageSharing: true,
      );
    }

    if (sharedPrayer == null) {
      return const _PrayerPermissions(
        canEdit: false,
        canLog: false,
        canAddUpdates: false,
        canManageSharing: false,
      );
    }

    PrayerCollaboratorModel? collaborator;
    for (final c in collaborators) {
      if (c.collaboratorUserId == currentUserId) {
        collaborator = c;
        break;
      }
    }
    final role = collaborator?.role;
    final canContribute = role == CollaboratorRole.owner ||
        role == CollaboratorRole.collaborator;

    return _PrayerPermissions(
      canEdit: sharedPrayer.allowEditing && canContribute,
      canLog: sharedPrayer.allowLogging,
      canAddUpdates: sharedPrayer.allowUpdates && canContribute,
      canManageSharing: false,
    );
  }

  Future<void> _markAsAnswered() async {
    try {
      final repository = ref.read(prayerRepositoryProvider);
      await repository.markAsAnswered(widget.prayerId);
      await _cancelReminder();

      // Notify collaborators best-effort — never block or surface errors.
      ref
          .read(sharedPrayerApiServiceProvider)
          .notifyAnswered(widget.prayerId)
          .catchError((_) {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prayer marked as answered')),
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

  Future<void> _restorePrayer() async {
    try {
      final repository = ref.read(prayerRepositoryProvider);
      await repository.updatePrayer(
        id: widget.prayerId,
        status: PrayerStatus.active,
      );
      if (mounted) {
        ref.invalidate(prayerByIdProvider(widget.prayerId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prayer restored to active')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _archivePrayer() async {
    try {
      final repository = ref.read(prayerRepositoryProvider);
      await repository.archivePrayer(widget.prayerId);
      await _cancelReminder();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prayer archived')),
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

  Future<void> _deletePrayer() async {
    try {
      final repository = ref.read(prayerRepositoryProvider);
      await repository.trashPrayer(widget.prayerId);
      await _cancelReminder();
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

  Future<void> _showLinkPromiseDialog() async {
    final userId = ref.read(currentUserIdProvider);
    final promiseRepo = ref.read(promiseRepositoryProvider);
    final allPromises = await promiseRepo.getAllPromises(userId);
    final linkedIds =
        ref.read(linkedPromiseIdsProvider(widget.prayerId)).valueOrNull ?? [];

    if (!mounted) return;

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => LinkPickerDialog<PromiseModel>(
        title: 'Link Promises',
        items: allPromises,
        alreadyLinkedIds: linkedIds.toSet(),
        getId: (p) => p.id,
        getLabel: (p) => p.reference,
        getSubtitle: (p) => p.content.length > 80
            ? '${p.content.substring(0, 80)}...'
            : p.content,
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      try {
        final linkRepo = ref.read(promisePrayerLinkRepositoryProvider);
        for (final promiseId in selected) {
          await linkRepo.linkPromiseToPrayer(
            promiseId: promiseId,
            prayerId: widget.prayerId,
            userId: userId,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Linked ${selected.length} promise${selected.length > 1 ? 's' : ''}'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error linking: $e')),
          );
        }
      }
    }
  }

  Future<void> _unlinkPromise(String promiseId) async {
    try {
      final linkRepo = ref.read(promisePrayerLinkRepositoryProvider);
      await linkRepo.unlinkPromiseFromPrayer(promiseId, widget.prayerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Promise unlinked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unlinking: $e')),
        );
      }
    }
  }

  Widget _buildLinkedPromisesSection() {
    final linkedAsync = ref.watch(linkedPromiseIdsProvider(widget.prayerId));

    return linkedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (promiseIds) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.link, size: 20, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text('Linked Promises',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showLinkPromiseDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            if (promiseIds.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No linked promises yet',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ...promiseIds.map((promiseId) => _LinkedPromiseTile(
                    promiseId: promiseId,
                    onRemove: () => _unlinkPromise(promiseId),
                    onTap: () => context.push('/promises/$promiseId'),
                  )),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash?'),
        content: const Text('Are you sure you want to move this prayer to trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePrayer();
            },
            child: const Text('Move to Trash', style: TextStyle(color: Colors.red)),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final prayerAsync = ref.watch(prayerByIdProvider(widget.prayerId));

    return prayerAsync.when(
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
              Text('Error loading prayer: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(prayerByIdProvider(widget.prayerId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (prayer) {
        if (prayer == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 0,
            ),
            body: const Center(child: Text('Prayer not found')),
          );
        }

        _initControllersFromPrayer(prayer);
        return _buildPrayerDetail(context, prayer);
      },
    );
  }

  Widget _buildPrayerDetail(BuildContext context, PrayerModel prayer) {
    final currentUserId = ref.watch(currentUserIdProvider);
    final sharedPrayer = ref.watch(sharedPrayerProvider(widget.prayerId)).valueOrNull;
    final collaborators =
        ref.watch(prayerCollaboratorsProvider(widget.prayerId)).valueOrNull ??
            const <PrayerCollaboratorModel>[];
    final permissions = _computePermissions(
      prayer: prayer,
      currentUserId: currentUserId,
      sharedPrayer: sharedPrayer,
      collaborators: collaborators,
    );

    // Watch structured updates from the new table
    final structuredUpdates =
        ref.watch(prayerUpdatesByPrayerProvider(widget.prayerId)).valueOrNull ??
            const <PrayerUpdateModel>[];

    // Build userId -> username map for attribution
    final userNameMap = <String, String>{};
    for (final c in collaborators) {
      userNameMap[c.collaboratorUserId] = c.collaboratorUsername;
    }
    // Owner is the prayer creator (use "You" for current user)
    String authorName(String userId) {
      if (userId == currentUserId) return 'You';
      return userNameMap[userId] ?? 'Unknown';
    }

    // Also show legacy updates embedded in content (for pre-migration data)
    final legacyUpdates = _parseLegacyUpdates(prayer.content);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (permissions.canManageSharing)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePrayerSheet.show(
                context,
                prayerId: widget.prayerId,
                prayerTitle: prayer.title,
              ),
            ),
          if (permissions.canManageSharing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _showDeleteConfirmation(context),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _isEditingTitle
                        ? TextField(
                            controller: _titleController,
                            autofocus: true,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            onSubmitted: (_) => _saveTitle(),
                          )
                        : Text(
                            prayer.title,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  if (permissions.canEdit) ...[
                    const SizedBox(width: 8),
                    if (_isEditingTitle)
                      IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: _saveTitle,
                        iconSize: 22,
                        visualDensity: VisualDensity.compact,
                        color: AppTheme.teal,
                      )
                    else
                      IconButton(
                        icon: Icon(Icons.edit_outlined,
                            size: 18, color: Colors.grey.shade400),
                        onPressed: () => setState(() => _isEditingTitle = true),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              StatusChip(label: prayer.status.displayName),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Description',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  if (permissions.canEdit)
                    if (_isEditingDescription)
                      TextButton.icon(
                        onPressed: _saveDescription,
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Save'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.teal,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      )
                    else
                      IconButton(
                        icon: Icon(Icons.edit_outlined,
                            size: 16, color: Colors.grey.shade400),
                        onPressed: () =>
                            setState(() => _isEditingDescription = true),
                        visualDensity: VisualDensity.compact,
                      ),
                ],
              ),
              const SizedBox(height: 4),
              if (_isEditingDescription) ...[
                _buildFormattingToolbar(),
                TextField(
                  controller: _descriptionController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null,
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    hintText: 'Write a description…',
                    hintStyle:
                        TextStyle(color: Colors.grey.shade400, fontSize: 16),
                  ),
                ),
              ] else
                _buildDescriptionContent(
                    _descriptionController.text, permissions.canEdit),
              const SizedBox(height: 16),
              _buildInfoRow(
                context,
                Icons.calendar_today,
                'Created ${_formatDate(DateTime.fromMillisecondsSinceEpoch(prayer.createdAt))}',
              ),
              const SizedBox(height: 8),
              _buildFrequencyRow(context, prayer, permissions.canEdit),
              ..._buildLinkedPeopleSection(prayer.category, permissions.canEdit),
              _buildLinkedPromisesSection(),
              const SizedBox(height: 24),
              Text(
                'Updates',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              // Show structured updates (newest first — already sorted by provider)
              ...structuredUpdates.map((update) {
                return TimelineItem(
                  text: update.content,
                  author: authorName(update.userId),
                  time: _formatDate(
                      DateTime.fromMillisecondsSinceEpoch(update.createdAt)),
                );
              }),
              // Show legacy updates (pre-migration data embedded in content)
              ...legacyUpdates.reversed.map((update) {
                final text = update['text'] as String? ?? '';
                final timestamp = update['timestamp'] as int? ?? 0;
                final time = timestamp > 0
                    ? _formatDate(
                        DateTime.fromMillisecondsSinceEpoch(timestamp))
                    : '';
                return TimelineItem(text: text, time: time);
              }),
              TimelineItem(
                text: 'Prayer created',
                time: _formatDate(
                    DateTime.fromMillisecondsSinceEpoch(prayer.createdAt)),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: permissions.canLog ? _showLogPrayerDialog : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Log Prayer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                    side: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (permissions.canManageSharing)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showShareToGroupSheet(context),
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Share to Group'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brandBlue,
                      side: const BorderSide(color: AppTheme.brandBlue),
                    ),
                  ),
                ),
              if (permissions.canManageSharing) const SizedBox(height: 12),
              if (prayer.status == PrayerStatus.active && permissions.canEdit)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _markAsAnswered,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Answered'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.teal,
                          side: const BorderSide(color: AppTheme.teal),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _archivePrayer,
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('Archive'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.mutedGrey,
                          side: const BorderSide(color: AppTheme.mutedGrey),
                        ),
                      ),
                    ),
                  ],
                ),
              if (prayer.status == PrayerStatus.archived && permissions.canEdit)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _restorePrayer,
                    icon: const Icon(Icons.unarchive_outlined),
                    label: const Text('Restore to Active'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brandPurple,
                      side: const BorderSide(color: AppTheme.brandPurple),
                    ),
                  ),
                ),
              if (prayer.status == PrayerStatus.answered && permissions.canEdit)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _restorePrayer,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reopen Prayer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brandPurple,
                      side: const BorderSide(color: AppTheme.brandPurple),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: permissions.canAddUpdates
                      ? () => _showAddUpdateBottomSheet(
                          context, collaborators)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Update'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateLinkedPeople(List<String> updatedIds) async {
    final currentPrayer = ref.read(prayerByIdProvider(widget.prayerId)).valueOrNull;
    if (currentPrayer == null) return;
    final meta = decodePrayerMetadata(currentPrayer.category);
    final newCategory = encodePrayerMetadata(
      PrayerMetadata(
        tags: meta.tags,
        linkedPeopleIds: updatedIds,
      ),
    );
    try {
      final repository = ref.read(prayerRepositoryProvider);
      await repository.updatePrayer(
        id: widget.prayerId,
        category: newCategory,
      );
      if (mounted) {
        ref.invalidate(prayerByIdProvider(widget.prayerId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating people: $e')),
        );
      }
    }
  }

  List<Widget> _buildLinkedPeopleSection(String? category, bool canEdit) {
    final meta = decodePrayerMetadata(category);
    final peopleIds = meta.linkedPeopleIds;
    final peopleAsync = ref.watch(peopleStreamProvider);

    if (peopleIds.isEmpty && !canEdit) return [];

    final allPeople = peopleAsync.valueOrNull ?? [];
    final isLoading = peopleAsync.isLoading && allPeople.isEmpty;

    final theme = Theme.of(context);

    return [
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.people, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...peopleIds.map((id) {
                  final person = allPeople.where((p) => p.id == id).firstOrNull;
                  // While the stream is loading, show a skeleton-ish placeholder.
                  final name = isLoading ? '…' : (person?.name ?? '?');
                  return Chip(
                    label: Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.08),
                    deleteIcon: canEdit
                        ? const Icon(Icons.close, size: 16)
                        : null,
                    onDeleted: canEdit
                        ? () {
                            final updated =
                                List<String>.from(peopleIds)..remove(id);
                            _updateLinkedPeople(updated);
                          }
                        : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }),
                if (canEdit)
                  ActionChip(
                    avatar: Icon(Icons.person_add,
                        size: 16, color: theme.colorScheme.primary),
                    label: Text('Add',
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500)),
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.08),
                    side: BorderSide(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                    onPressed: () => _showAddPersonSheet(peopleIds),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  void _showAddPersonSheet(List<String> currentIds) {
    final allPeople = ref.read(peopleStreamProvider).valueOrNull ?? [];
    final available = allPeople.where((p) => !currentIds.contains(p.id)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No more people to add')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Link a Person',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...available.map((person) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(person.name),
                    onTap: () {
                      Navigator.pop(context);
                      final updated = [...currentIds, person.id];
                      _updateLinkedPeople(updated);
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFrequencyRow(
      BuildContext context, PrayerModel prayer, bool canEdit) {
    return GestureDetector(
      onTap: canEdit ? () => _showFrequencyPicker(prayer) : null,
      child: Row(
        children: [
          Icon(Icons.repeat, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            prayer.frequency.displayName,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          if (canEdit) ...[
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 14, color: Colors.grey.shade400),
          ],
        ],
      ),
    );
  }

  Future<void> _showFrequencyPicker(PrayerModel prayer) async {
    final selected = await showModalBottomSheet<PrayerFrequency>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Prayer Frequency',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...PrayerFrequency.values.map((freq) => ListTile(
                    leading: Icon(
                      freq == prayer.frequency
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: freq == prayer.frequency
                          ? AppTheme.brandPurple
                          : Colors.grey.shade400,
                    ),
                    title: Text(freq.displayName),
                    onTap: () => Navigator.pop(context, freq),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected != null && selected != prayer.frequency && mounted) {
      try {
        final repository = ref.read(prayerRepositoryProvider);
        await repository.updatePrayer(
          id: widget.prayerId,
          frequency: selected,
        );
        if (mounted) {
          ref.invalidate(prayerByIdProvider(widget.prayerId));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating frequency: $e')),
          );
        }
      }
    }
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  void _showAddUpdateBottomSheet(
    BuildContext context,
    List<PrayerCollaboratorModel> collaborators,
  ) {
    final textController = TextEditingController();

    void insertMention(String username, StateSetter setSheetState) {
      final text = textController.text;
      final selection = textController.selection;
      final offset = selection.isValid ? selection.baseOffset : text.length;
      final before = text.substring(0, offset);
      final after = text.substring(offset);
      final mention = '@$username ';
      textController.text = '$before$mention$after';
      textController.selection =
          TextSelection.collapsed(offset: offset + mention.length);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Add Update',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TextField(
                          controller: textController,
                          maxLines: null,
                          expands: true,
                          textCapitalization: TextCapitalization.sentences,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            hintText: 'Write your update here...',
                            hintStyle: const TextStyle(
                                color: Color.fromARGB(255, 189, 189, 189)),
                            filled: true,
                            fillColor:
                                const Color.fromARGB(255, 251, 250, 250),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      // @ mention button row (only if collaborators exist)
                      if (collaborators.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 32,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              Icon(Icons.alternate_email,
                                  size: 18, color: Colors.grey.shade500),
                              const SizedBox(width: 8),
                              ...collaborators.map((c) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ActionChip(
                                      label: Text(
                                        '@${c.collaboratorUsername}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      onPressed: () => insertMention(
                                          c.collaboratorUsername,
                                          setSheetState),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: AppTheme.brandPurple
                                          .withValues(alpha: 0.08),
                                      side: BorderSide.none,
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                              label: const Text('Cancel'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.mutedGrey,
                                side: const BorderSide(
                                    color: AppTheme.mutedGrey),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final updateText =
                                    textController.text.trim();
                                if (updateText.isNotEmpty) {
                                  _addUpdate(updateText);
                                  Navigator.of(context).pop();
                                }
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Add'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).primaryColor,
                                side: BorderSide(
                                    color: Theme.of(context).primaryColor),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _PrayerPermissions {
  final bool canEdit;
  final bool canLog;
  final bool canAddUpdates;
  final bool canManageSharing;

  const _PrayerPermissions({
    required this.canEdit,
    required this.canLog,
    required this.canAddUpdates,
    required this.canManageSharing,
  });
}

/// A small icon button used in the description formatting toolbar.
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
          child: Icon(icon, size: 20, color: Colors.grey.shade700),
        ),
      ),
    );
  }
}

/// A single linked promise tile that resolves the promise reference reactively.
class _LinkedPromiseTile extends ConsumerWidget {
  final String promiseId;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _LinkedPromiseTile({
    required this.promiseId,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promiseAsync = ref.watch(promiseByIdProvider(promiseId));

    return promiseAsync.when(
      loading: () => const ListTileSkeleton(hasLeading: false),
      error: (_, _) => const SizedBox.shrink(),
      data: (promise) {
        if (promise == null || promise.isDeleted) return const SizedBox.shrink();
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.bookmark,
              size: 20, color: AppTheme.coral),
          title: Text(
            promise.reference,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: promise.content.isNotEmpty
              ? Text(
                  promise.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                )
              : null,
          trailing: IconButton(
            icon: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
          ),
          onTap: onTap,
        );
      },
    );
  }
}
