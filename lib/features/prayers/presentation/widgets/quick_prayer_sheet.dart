import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/domain/enums/prayer_enums.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/models/prayer_metadata_codec.dart';
import '../../../../core/sync/models/prayer_model.dart';

/// Capture a prayer in one field.
///
/// The full form asks eight sections for something that is usually one
/// sentence — and only the title is required. That ordering is backwards: a
/// form showing seven optional sections reads as a form wanting seven
/// answers, and it is where a first-time user stops.
///
/// Here the optional fields are *additive*: a row of chips that each expand
/// in place and then collapse into the value you chose. An untouched prayer
/// is one field; a fully specified one reaches every field the model has.
/// The long form remains as the edit view, where the prayer exists and its
/// fields have something to describe.
/// Returns the prayer that was created, or null if the sheet was dismissed.
///
/// Callers that only want the sheet can ignore the result. The group flow
/// needs it: it used to push the full add-prayer screen and then guess which
/// prayer had just been made by taking the newest from the stream, which
/// picked the wrong one if the user cancelled or a sync delivered something
/// newer first.
Future<PrayerModel?> showQuickPrayerSheet(BuildContext context) {
  return showModalBottomSheet<PrayerModel>(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _QuickPrayerSheet(),
  );
}

class _QuickPrayerSheet extends ConsumerStatefulWidget {
  const _QuickPrayerSheet();

  @override
  ConsumerState<_QuickPrayerSheet> createState() => _QuickPrayerSheetState();
}

class _QuickPrayerSheetState extends ConsumerState<_QuickPrayerSheet> {
  final _controller = TextEditingController();
  final _tagController = TextEditingController();

  PrayerFrequency? _frequency;
  DateTime? _reminder;
  final List<String> _tags = [];
  final List<String> _peopleIds = [];

  /// Which chip is currently expanded. Only one at a time — the sheet stays
  /// short, and the choice being made is unambiguous.
  String? _open;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _tagController.dispose();
    super.dispose();
  }

  bool get _canSave => _controller.text.trim().isNotEmpty && !_saving;

  @override
  Widget build(BuildContext context) {
    final strings = l10n(context);
    return Padding(
      // Sits above the keyboard: this sheet is opened to type into.
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.subtleFill,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 18, height: 1.4),
                decoration: InputDecoration(
                  hintText: strings.whatAreYouPrayingFor,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  hintStyle: TextStyle(fontSize: 18, color: context.hintText),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              _chipRow(strings),
              if (_open != null) ...[
                const SizedBox(height: 12),
                _expanded(strings),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canSave ? _save : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(_saving ? strings.saving : strings.actionSave),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The optional fields, as things you may add rather than sections to pass.
  /// A chip that has a value shows it, so the sheet doubles as a summary.
  Widget _chipRow(AppLocalizations strings) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          id: 'person',
          icon: Icons.person_add_alt_1_outlined,
          label: _peopleIds.isEmpty
              ? strings.person
              : strings.nPeople(_peopleIds.length),
          filled: _peopleIds.isNotEmpty,
        ),
        _chip(
          id: 'repeat',
          icon: Icons.repeat_rounded,
          label: _frequency?.displayName ?? strings.repeatLabel,
          filled: _frequency != null,
        ),
        _chip(
          id: 'remind',
          icon: Icons.alarm_outlined,
          label: _reminder == null
              ? strings.remind
              : TimeOfDay.fromDateTime(_reminder!).format(context),
          filled: _reminder != null,
        ),
        _chip(
          id: 'tag',
          icon: Icons.local_offer_outlined,
          label: _tags.isEmpty ? strings.tag : _tags.join(', '),
          filled: _tags.isNotEmpty,
        ),
      ],
    );
  }

  Widget _chip({
    required String id,
    required IconData icon,
    required String label,
    required bool filled,
  }) {
    final open = _open == id;
    final accent = AppTheme.accentOnTintFor(
        AppTheme.brandBlue, Theme.of(context).brightness);
    return ActionChip(
      avatar: Icon(icon,
          size: 18, color: filled || open ? accent : context.mutedText),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
        color: filled || open ? accent : context.primaryText,
      ),
      backgroundColor: filled || open
          ? accent.withValues(alpha: AppTheme.alphaLight)
          : Colors.transparent,
      side: BorderSide(
          color: filled || open ? accent.withValues(alpha: 0.4)
              : context.hairline),
      onPressed: () => setState(() => _open = open ? null : id),
    );
  }

  Widget _expanded(AppLocalizations strings) {
    switch (_open) {
      case 'repeat':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in PrayerFrequency.values)
              ChoiceChip(
                label: Text(f.displayName),
                selected: _frequency == f,
                onSelected: (_) => setState(
                    () => _frequency = _frequency == f ? null : f),
              ),
          ],
        );
      case 'remind':
        return Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule, size: 18),
              label: Text(_reminder == null
                  ? strings.pickATime
                  : TimeOfDay.fromDateTime(_reminder!).format(context)),
              onPressed: _pickReminder,
            ),
            if (_reminder != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _reminder = null),
                child: Text(strings.clear),
              ),
            ],
          ],
        );
      case 'tag':
        return Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagController,
                decoration: InputDecoration(
                  hintText: strings.addATag,
                  isDense: true,
                ),
                onSubmitted: _addTag,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: strings.addATag,
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _addTag(_tagController.text),
            ),
          ],
        );
      case 'person':
        final people = ref.watch(peopleStreamProvider).valueOrNull ?? const [];
        if (people.isEmpty) {
          return Text(strings.noPeopleAddedYet,
              style: TextStyle(color: context.mutedText));
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in people)
              FilterChip(
                label: Text(p.name),
                selected: _peopleIds.contains(p.id),
                onSelected: (on) => setState(() =>
                    on ? _peopleIds.add(p.id) : _peopleIds.remove(p.id)),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  Future<void> _pickReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    // The sheet can be dismissed while the picker is up (a pop, or the app
    // being killed and restored), and setState on a disposed State throws.
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    setState(() => _reminder =
        DateTime(now.year, now.month, now.day, picked.hour, picked.minute));
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // First line is the title, the rest is the body — the same split the note
    // editor uses. Asking which is which is a question with no wrong answer,
    // so it should not be asked.
    final lines = text.split('\n');
    final title = lines.first.trim();
    final content = lines.skip(1).join('\n').trim();

    final strings = l10n(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    try {
      final repository = ref.read(prayerRepositoryProvider);
      final prayer = await repository.createPrayer(
        userId: ref.read(currentUserIdProvider),
        title: title,
        content: content,
        frequency: _frequency ?? PrayerFrequency.asNeeded,
        category: (_tags.isEmpty && _peopleIds.isEmpty)
            ? ''
            : encodePrayerMetadata(PrayerMetadata(
                tags: List<String>.from(_tags),
                linkedPeopleIds: List<String>.from(_peopleIds),
              )),
        reminderAt: _reminder?.millisecondsSinceEpoch,
      );

      if (_reminder != null) {
        try {
          await ref
              .read(prayerReminderServiceProvider)
              .schedulePrayerReminderAt(prayer, preferredTime: _reminder);
        } catch (e) {
          // The prayer is saved; only the reminder failed. Surfacing a
          // failure here would suggest the prayer was lost, which it was not.
          debugPrint('Prayer reminder scheduling failed: $e');
        }
      }

      navigator.pop(prayer);
      messenger.showSnackBar(SnackBar(
        content: Text(strings.prayerSavedSuccessfully),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(UserFacingError.message(e, action: 'save this prayer')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.errorSurface,
      ));
    }
  }
}
