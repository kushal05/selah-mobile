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
import '../../../../shared/widgets/undo_snackbar.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_label.dart';

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
            SnackBar(content: Text(UserFacingError.message(e, action: 'save your changes'))),
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
        l10n(context).noDescription,
        style: TextStyle(fontSize: 16, color: context.mutedText),
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
            SnackBar(content: Text(UserFacingError.message(e, action: 'save your changes'))),
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
          SnackBar(content: Text(l10n(context).updateAdded)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.forLoad(e))),
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
          SnackBar(
            content: Text(l10n(context).prayerLogged),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'log prayer')),
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
        title: Text(l10n(context).logPrayer),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: l10n(context).optionalNote,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n(context).log),
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
        SnackBar(
          content: Text(l10n(context).youAreNotAMemberOfAnyGroups),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<GroupModel>(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
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
                      l10n(context).shareToGroup,
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
                          fontSize: 16,
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
              content: Text(UserFacingError.message(e, action: 'share')),
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
          SnackBar(content: Text(l10n(context).prayerMarkedAsAnswered)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.forLoad(e))),
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
          SnackBar(content: Text(l10n(context).prayerRestoredToActive)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.forLoad(e))),
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
          SnackBar(content: Text(l10n(context).prayerArchived)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.forLoad(e))),
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
        showUndoSnackBar(
          context,
          itemLabel: 'Prayer',
          onUndo: () => repository.restorePrayer(widget.prayerId),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.forLoad(e))),
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

    final selected = await LinkPicker.show<PromiseModel>(
      context,
      title: l10n(context).linkPromises,
      items: allPromises,
      alreadyLinkedIds: linkedIds.toSet(),
      getId: (p) => p.id,
      getLabel: (p) => p.reference,
      getSubtitle: (p) => p.content.length > 120
          ? '${p.content.substring(0, 120)}…'
          : p.content,
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
            SnackBar(content: Text(UserFacingError.message(e, action: 'link that'))),
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
          SnackBar(content: Text(l10n(context).promiseUnlinked)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.message(e, action: 'unlink that'))),
        );
      }
    }
  }

  Widget _buildLinkedPromisesSection({required bool canEdit}) {
    final linkedAsync = ref.watch(linkedPromiseIdsProvider(widget.prayerId));

    return linkedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (promiseIds) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                // Same leading glyph size as the linked-people row above it;
                // these were 20 and 16, with one carrying a titleMedium
                // heading and the other nothing, so two sibling rows read as
                // two unrelated components.
                Icon(Icons.link,
                    size: AppTheme.iconMD,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  l10n(context).linkedPromises,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                _AddLink(
                  label: l10n(context).add,
                  onPressed: _showLinkPromiseDialog,
                ),
              ],
            ),
            if (promiseIds.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n(context).noLinkedPromisesYet,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.mutedText,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              // Chips, like the linked-people row directly above. These were
              // full ListTiles, so two sibling relationships on the same
              // screen were presented as two different kinds of object.
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: promiseIds
                      .map((promiseId) => _LinkedPromiseChip(
                            promiseId: promiseId,
                            onRemove: canEdit
                                ? () => _unlinkPromise(promiseId)
                                : null,
                            onTap: () =>
                                context.push('/promises/$promiseId'),
                          ))
                      .toList(),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).moveToTrash2),
        content: Text(l10n(context).areYouSureYouWantToMoveThisPrayerToTrash),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePrayer();
            },
            child: Text(l10n(context).moveToTrash, style: TextStyle(color: context.dangerText)),
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
              Text(UserFacingError.forLoad(error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(prayerByIdProvider(widget.prayerId)),
                child: Text(l10n(context).retry),
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
            body: Center(child: Text(l10n(context).prayerNotFound)),
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
          tooltip: l10n(context).actionBack,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (permissions.canManageSharing)
            IconButton(
              tooltip: l10n(context).sharePrayer,
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePrayerSheet.show(
                context,
                prayerId: widget.prayerId,
                prayerTitle: prayer.title,
              ),
            ),
          if (permissions.canManageSharing)
            IconButton(
              tooltip: l10n(context).deletePrayer,
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
                            decoration: AppTheme.inlineInput(),
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
                        tooltip: l10n(context).saveTitle,
                        icon: const Icon(Icons.check),
                        onPressed: _saveTitle,
                        iconSize: 22,
                        visualDensity: VisualDensity.compact,
                        color: AppTheme.teal,
                      )
                    else
                      IconButton(
                        tooltip: l10n(context).editTitle,
                        icon: Icon(Icons.edit_outlined,
                            size: 18, color: context.hintText),
                        onPressed: () => setState(() => _isEditingTitle = true),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // One meta line instead of a stacked chip and a labelled
              // section: status and cadence are two facts about the same
              // prayer and belong on one row.
              Row(
                children: [
                  StatusChip(label: prayer.status.displayName),
                  const SizedBox(width: 8),
                  if (permissions.canEdit)
                    Semantics(
                      button: true,
                      child: InkWell(
                        onTap: () => _showFrequencyPicker(prayer),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(prayer.frequency.displayName,
                                  style: TextStyle(
                                      fontSize: 13, color: context.mutedText)),
                              const SizedBox(width: 2),
                              Icon(Icons.arrow_drop_down,
                                  size: 18, color: context.mutedText),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Text(prayer.frequency.displayName,
                        style:
                            TextStyle(fontSize: 13, color: context.mutedText)),
                  const Spacer(),
                  if (permissions.canEdit)
                    if (_isEditingDescription)
                      TextButton.icon(
                        onPressed: _saveDescription,
                        icon: const Icon(Icons.check, size: 16),
                        label: Text(l10n(context).actionSave),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.teal,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: l10n(context).editDescription,
                        icon: Icon(Icons.edit_outlined,
                            size: 16, color: context.hintText),
                        onPressed: () =>
                            setState(() => _isEditingDescription = true),
                        visualDensity: VisualDensity.compact,
                      ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isEditingDescription) ...[
                _buildFormattingToolbar(),
                TextField(
                  controller: _descriptionController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null,
                  style: const TextStyle(fontSize: 16),
                  decoration: AppTheme.inlineInput(hint: l10n(context).writeADescription),
                ),
              ] else
                _buildDescriptionContent(
                    _descriptionController.text, permissions.canEdit),
              const SizedBox(height: 24),

              // Details were a flat run of rows and headings at the same
              // visual weight as the prayer itself, so nothing said where one
              // thing ended and the next began. Grouped into two labelled
              // cards: what this prayer *is*, then what has happened to it.
              _DetailSection(
                title: l10n(context).details,
                children: [
                  _buildInfoRow(
                    context,
                    Icons.calendar_today,
                    'Created ${_formatDate(DateTime.fromMillisecondsSinceEpoch(prayer.createdAt))}',
                  ),
                  ..._buildLinkedPeopleSection(
                      prayer.category, permissions.canEdit),
                  _buildLinkedPromisesSection(
                      canEdit: permissions.canEdit),
                ],
              ),
              const SizedBox(height: 20),
              SectionLabel(l10n(context).actions),
              const SizedBox(height: 12),
              // Four stacked full-width buttons used a whole screen of height
              // for four taps. Two equal columns instead — a plain Wrap sized
              // each chip to its label, so "Log Prayer" and "Archive" came
              // out different widths and the block looked accidental.
              _ActionGrid(
                children: [
                  _PrayerAction(
                    icon: Icons.check_rounded,
                    label: l10n(context).logPrayer,
                    accent: AppTheme.brandBlue,
                    onPressed: permissions.canLog ? _showLogPrayerDialog : null,
                  ),
                  if (permissions.canManageSharing)
                    _PrayerAction(
                      icon: Icons.group_add_outlined,
                      label: l10n(context).shareToGroup,
                      accent: AppTheme.teal,
                      onPressed: () => _showShareToGroupSheet(context),
                    ),
                  if (prayer.status == PrayerStatus.active &&
                      permissions.canEdit) ...[
                    _PrayerAction(
                      icon: Icons.check_circle_outline_rounded,
                      label: l10n(context).answered,
                      accent: AppTheme.emerald,
                      onPressed: _markAsAnswered,
                    ),
                    _PrayerAction(
                      icon: Icons.archive_outlined,
                      label: l10n(context).archive,
                      accent: AppTheme.mutedGrey,
                      onPressed: _archivePrayer,
                    ),
                  ],
                  if (prayer.status == PrayerStatus.archived &&
                      permissions.canEdit)
                    _PrayerAction(
                      icon: Icons.unarchive_outlined,
                      label: l10n(context).restoreToActive,
                      accent: AppTheme.brandBlue,
                      onPressed: _restorePrayer,
                    ),
                  if (prayer.status == PrayerStatus.answered &&
                      permissions.canEdit)
                    _PrayerAction(
                      icon: Icons.refresh_rounded,
                      label: l10n(context).reopenPrayer,
                      accent: AppTheme.brandPurple,
                      onPressed: _restorePrayer,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              SectionLabel(l10n(context).activity),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: permissions.canAddUpdates
                      ? () => _showAddUpdateBottomSheet(
                          context, collaborators)
                      : null,
                  icon: const Icon(Icons.add),
                  label: Text(l10n(context).addUpdate),
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
          SnackBar(content: Text(UserFacingError.message(e, action: 'update the linked people'))),
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
          Icon(Icons.people,
              size: AppTheme.iconMD,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                        fontSize: 14,
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
              ],
            ),
          ),
          if (canEdit)
            _AddLink(
              label: l10n(context).add,
              onPressed: () => _showAddPersonSheet(peopleIds),
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
        SnackBar(content: Text(l10n(context).noMorePeopleToAdd)),
      );
      return;
    }

    showModalBottomSheet(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
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
                  l10n(context).linkAPerson,
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


  Future<void> _showFrequencyPicker(PrayerModel prayer) async {
    final selected = await showModalBottomSheet<PrayerFrequency>(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
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
                  l10n(context).prayerFrequency,
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
                          : context.hintText,
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
            SnackBar(content: Text(UserFacingError.message(e, action: 'update how often you pray this'))),
          );
        }
      }
    }
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
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
                            l10n(context).addUpdate,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            tooltip: l10n(context).close,
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
                            hintText: l10n(context).writeYourUpdateHere,
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
                                  size: 18, color: context.mutedText),
                              const SizedBox(width: 8),
                              ...collaborators.map((c) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ActionChip(
                                      label: Text(
                                        '@${c.collaboratorUsername}',
                                        style: const TextStyle(fontSize: 13),
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
                              label: Text(l10n(context).actionCancel),
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
                              label: Text(l10n(context).add),
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
          child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// A single linked promise tile that resolves the promise reference reactively.


/// A labelled group of related detail rows.
///
/// The detail screen ran metadata, linked people, linked promises and the
/// update history together as one column of rows, all at body weight. The
/// card gives the group an edge, and the label says what the group is.
class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title),
        const SizedBox(height: 10),
        // No card around this. Details are reference — a filled, bordered
        // panel gave them more weight than the prayer's own title and words,
        // which are what the screen is about. The label alone is enough to
        // group them.
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ],
    );
  }
}



/// The one "Add" control used by every linked-items row on this screen.
///
/// These were previously a TextButton.icon in one row and an ActionChip in
/// the next — same job, two shapes, two icon sizes. One component means the
/// rows read as siblings.
class _AddLink extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _AddLink({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded, size: AppTheme.iconMD),
      label: Text(label),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing8),
        minimumSize: const Size(0, 36),
      ),
    );
  }
}


/// One action on the prayer, sized to its label rather than to the screen.
///
/// Tinted rather than outlined so the set reads as a group of related
/// choices, with the accent carrying the meaning — answered is green,
/// archive is grey — instead of four identically-outlined bars.
class _PrayerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onPressed;

  const _PrayerAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final enabled = onPressed != null;
    final glyph = enabled
        ? AppTheme.accentOnTintFor(accent, brightness)
        : context.hintText;
    final ink = enabled
        ? AppTheme.inkOnTintFor(accent, brightness)
        : context.hintText;

    return Material(
      color: enabled
          ? glyph.withValues(alpha: AppTheme.alphaLight)
          : context.subtleFill,
      borderRadius: AppTheme.borderRadius2XL,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppTheme.borderRadius2XL,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppTheme.iconMD, color: glyph),
              const SizedBox(width: AppTheme.spacing8),
              // Flexible so a long label ellipsises inside its column rather
              // than forcing the row wider than its half.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// A linked promise, shaped like the person chips beside it.
class _LinkedPromiseChip extends ConsumerWidget {
  final String promiseId;
  final VoidCallback? onRemove;
  final VoidCallback onTap;

  const _LinkedPromiseChip({
    required this.promiseId,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final promise = ref.watch(promiseByIdProvider(promiseId)).valueOrNull;
    final label = promise?.reference ?? '…';

    return InputChip(
      avatar: Icon(Icons.bookmark_outline_rounded,
          size: 16, color: theme.colorScheme.primary),
      label: Text(
        label,
        style: TextStyle(fontSize: 14, color: theme.colorScheme.primary),
      ),
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      onPressed: onTap,
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 16),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}


/// Lays its children out in two equal columns.
///
/// [Wrap] sizes each child to its content, which leaves ragged right edges
/// and rows of different heights. These are peers — a fixed half-width each
/// makes the set read as one block of choices, and an odd last item spans
/// the full width rather than sitting alone at half.
class _ActionGrid extends StatelessWidget {
  final List<Widget> children;

  const _ActionGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    const gap = AppTheme.spacing10;
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - gap) / 2;
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += 2) {
          final isLast = i + 1 >= children.length;
          rows.add(Padding(
            padding: EdgeInsets.only(bottom: i + 2 < children.length ? gap : 0),
            child: Row(
              children: [
                SizedBox(
                    width: isLast ? constraints.maxWidth : half,
                    child: children[i]),
                if (!isLast) ...[
                  const SizedBox(width: gap),
                  SizedBox(width: half, child: children[i + 1]),
                ],
              ],
            ),
          ));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
      },
    );
  }
}
