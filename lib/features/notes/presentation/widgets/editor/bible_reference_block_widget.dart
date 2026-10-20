import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../bible/domain/models/bible_reference.dart';
import '../../../../bible/domain/models/bible_version_info.dart';
import '../../../../../core/providers/motion_preferences.dart';
import '../../../../../core/theme/theme_colors.dart';
import '../../../../../core/sync/providers/sync_providers.dart';
import '../../../../../l10n/l10n.dart';
import '../../../../../shared/widgets/selectable_chip.dart';
import '../../../../../shared/widgets/tap_target.dart';

/// Renders a Bible verse block in the note editor as a collapsible card.
///
/// Collapsed: shows only the reference line (e.g. "John 3:16 (KJV)").
/// Expanded:  shows the reference line plus the verse text.
/// Tap toggles expand/collapse. Long-press opens the options sheet.
class BibleReferenceBlockWidget extends ConsumerStatefulWidget {
  final BibleReference reference;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onChangeVersion;
  final VoidCallback? onTap;

  /// Called with the new tag ids when the user tags or untags this reference.
  final ValueChanged<List<String>>? onTagsChanged;

  /// Available translations from the Bible DB, used by the version picker.
  final List<String> availableTranslations;

  const BibleReferenceBlockWidget({
    super.key,
    required this.reference,
    this.onRemove,
    this.onEdit,
    this.onChangeVersion,
    this.onTap,
    this.onTagsChanged,
    this.availableTranslations = const [],
  });

  @override
  ConsumerState<BibleReferenceBlockWidget> createState() =>
      _BibleReferenceBlockWidgetState();
}

class _BibleReferenceBlockWidgetState
    extends ConsumerState<BibleReferenceBlockWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  bool _addingTag = false;
  final _tagController = TextEditingController();
  final _tagFocusNode = FocusNode();
  late final AnimationController _iconController;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0, // start expanded (chevron rotated)
    );
  }

  @override
  void dispose() {
    _iconController.dispose();
    _tagController.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitTag() async {
    final name = _tagController.text.trim();
    _tagController.clear();
    if (name.isEmpty) {
      setState(() => _addingTag = false);
      return;
    }
    final repo = ref.read(tagRepositoryProvider);
    final userId = ref.read(currentUserIdProvider);
    final tag = await repo.getOrCreateTag(name, userId);
    if (!mounted) return;
    setState(() => _addingTag = false);
    final current = widget.reference.tagIds;
    if (current.contains(tag.id)) return;
    widget.onTagsChanged?.call([...current, tag.id]);
  }

  void _removeTag(String tagId) {
    widget.onTagsChanged?.call(
      widget.reference.tagIds.where((id) => id != tagId).toList(),
    );
  }

  /// Tags on this reference, and the control to add one.
  ///
  /// Right-aligned under the verse text: it belongs to the whole reference
  /// rather than to any one line of it, and putting it at the end keeps the
  /// verse itself the first thing read.
  /// The reference's tags, under the verse and aligned with it, and the field
  /// for a new one while it is being added. Adding one starts from the ⋮ menu
  /// with the card's other actions; the control used to sit alone at the
  /// bottom-right, apart from everything else it belonged with.
  Widget _buildTagRow() {
    if (widget.onTagsChanged == null) return const SizedBox.shrink();

    final tagIds = widget.reference.tagIds;
    final names = {
      for (final t in ref.watch(tagsStreamProvider).valueOrNull ?? const [])
        t.id: t.name,
    };
    // A tag whose name has not arrived yet is skipped rather than shown as a
    // raw id.
    final shown = [for (final id in tagIds) if (names[id] != null) id];
    if (shown.isEmpty && !_addingTag) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final id in shown)
            SelectableChip(
              label: names[id]!,
              isSelected: true,
              showDelete: true,
              accent: AppTheme.brandPurple,
              onTap: () => _removeTag(id),
            ),
          if (_addingTag)
            SizedBox(
              width: 140,
              child: TextField(
                controller: _tagController,
                focusNode: _tagFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.done,
                style: AppTheme.caption.copyWith(color: context.primaryText),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l10n(context).enterTagName,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onSubmitted: (_) => _submitTag(),
                onTapOutside: (_) => _submitTag(),
              ),
            ),
        ],
      ),
    );
  }

  /// Opens the field for a new tag — opening the card first if it is closed,
  /// since the field sits under the verse — and puts the cursor in it.
  ///
  /// The focus has to be asked for: the field's autofocus only takes it when
  /// nothing on the page has it, and in the editor a line of the note almost
  /// always does — the sheet closing hands focus back to it, so the tag typed
  /// went into the note instead.
  void _startAddingTag() {
    setState(() {
      _expanded = true;
      _addingTag = true;
    });
    _iconController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _addingTag) _tagFocusNode.requestFocus();
    });
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _iconController.forward();
    } else {
      _iconController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ref = widget.reference;
    final hasText = !ref.pending && ref.text.isNotEmpty;

    return Semantics(
      button: true,
      child: GestureDetector(
      onTap: widget.onTap ?? (hasText ? _toggle : null),
      onLongPress: () => _showOptions(context),
      child: AnimatedSize(
        duration: context.motion(const Duration(milliseconds: 200)),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          // Less at the top and right than elsewhere: the action icons' 44pt
          // touch areas carry their own margin there, and the full 14 on top
          // of it pushed the icons in from the corner and made the card tall.
          // The verse below takes the difference back on its right.
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 14),
          decoration: BoxDecoration(
            color: AppTheme.brandPurple.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.brandPurple.withValues(alpha: 0.15),
            ),
          ),
          // The verse runs the card's full width below the reference row. It
          // used to sit in the row's middle column, between the book icon and
          // the action icons, which left it a narrow strip down the centre of
          // the card — the more so on a phone, with the edit and remove icons
          // both showing.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Bookmark icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.brandPurple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.menu_book,
                      size: 18,
                      color: context.accentInk(AppTheme.brandPurple),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Reference line (e.g., "John 3:16-18")
                  Expanded(
                    child: Text(
                      ref.displayReference,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.accentInk(AppTheme.brandPurple),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  // Action icons + chevron
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Edit, the action used most, stays in the row; the
                      // rest — tag, change version, remove, copy — are in the
                      // menu. With a full 44pt touch area each, tag, edit and
                      // remove side by side left the reference about 130pt,
                      // and even "John 3:16-17 (KJV)" wrapped. The menu is the
                      // sheet a long-press opened, which nothing on screen
                      // ever pointed to.
                      if (widget.onEdit != null)
                        _ActionIcon(
                          icon: Icons.edit_outlined,
                          tooltip: l10n(context).editReference,
                          onTap: widget.onEdit!,
                        ),
                      _ActionIcon(
                        icon: Icons.more_vert_rounded,
                        tooltip: l10n(context)
                            .moreActionsFor(ref.displayReference),
                        onTap: () => _showOptions(context),
                      ),
                      if (hasText)
                        RotationTransition(
                          turns: Tween(begin: 0.0, end: 0.5).animate(
                            CurvedAnimation(
                              parent: _iconController,
                              curve: Curves.easeInOut,
                            ),
                          ),
                          // Not a button (tapping anywhere on the card opens and
                          // closes it), so a plain box, sized to sit in line
                          // with the touch areas beside it.
                          child: SizedBox(
                            width: 32,
                            height: AppTheme.minTapTarget,
                            child: Icon(
                              Icons.expand_more,
                              size: 20,
                              color: context.accentInk(AppTheme.brandPurple),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              // Verse text — only visible when expanded
              if (_expanded)
                Padding(
                  // Back to the card's 14 on the right; see the padding above.
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ref.pending || ref.text.isEmpty)
                        Text(
                          l10n(context).verseTextPendingDownload,
                          style: TextStyle(
                            fontSize: _verseFontSize,
                            fontStyle: FontStyle.italic,
                            color: context.mutedText,
                            height: 1.5,
                          ),
                        )
                      else
                        _buildVerseText(theme),
                      _buildTagRow(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  /// The verse is quoted material inside a note, so it is set a step below the
  /// note's own 16pt body text, which kept it from reading as the note itself.
  static const double _verseFontSize = 14;
  static const double _verseNumberFontSize = 11;

  /// Build verse text with optional superscript verse numbers
  Widget _buildVerseText(ThemeData theme) {
    final ref = widget.reference;
    final baseColor =
        theme.textTheme.bodyMedium?.color ?? context.mutedText;
    final showNumbers =
        ref.display.showVerseNumbers && ref.text.length > 1;

    if (!showNumbers) {
      return Text(
        ref.fullText,
        style: TextStyle(
          fontSize: _verseFontSize,
          fontStyle: FontStyle.italic,
          color: baseColor,
          height: 1.5,
        ),
      );
    }

    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: _verseFontSize,
          fontStyle: FontStyle.italic,
          color: baseColor,
          height: 1.5,
        ),
        children: ref.text.map((vt) {
          return TextSpan(
            children: [
              TextSpan(
                text: '${vt.verse} ',
                style: TextStyle(
                  fontSize: _verseNumberFontSize,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.normal,
                  color: context.accentInk(AppTheme.brandPurple),
                ),
              ),
              TextSpan(text: '${vt.content} '),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      // Defaults to false: a scroll-controlled sheet otherwise draws its
      // top edge behind the notch or Dynamic Island.
      useSafeArea: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // Scrolls when it does not fit. A sheet like this is held to 9/16 of the
      // screen, and with six actions — tag and version now among them — that
      // ran out on a small phone or at a large text size.
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: context.subtleFill,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(l10n(context).copyVerseText),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.reference.fullText));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n(context).verseTextCopied),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: Text(l10n(context).copyReference),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.reference.displayReference));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(l10n(context).referenceCopied),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              if (widget.onEdit != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n(context).editReference),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onEdit?.call();
                  },
                ),
              if (widget.onTagsChanged != null)
                ListTile(
                  leading: const Icon(Icons.local_offer_outlined),
                  title: Text(l10n(context).addTag),
                  onTap: () {
                    Navigator.pop(context);
                    _startAddingTag();
                  },
                ),
              // Only with another version to change to; the picker shows nothing
              // with one.
              if (widget.onChangeVersion != null &&
                  widget.availableTranslations.length > 1)
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: Text(l10n(context).changeVersion),
                  onTap: () {
                    Navigator.pop(context);
                    _showVersionPicker(context);
                  },
                ),
              if (widget.onRemove != null)
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: context.dangerText),
                  title: Text(l10n(context).removeReference,
                      style: TextStyle(color: context.dangerText)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onRemove?.call();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }


  void _showVersionPicker(BuildContext context) {
    final translations = widget.availableTranslations;
    if (translations.isEmpty) return;

    final currentVersion = widget.reference.reference.version.toUpperCase();

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n(context).selectVersion),
        children: translations.map((code) {
          final isSelected = code == currentVersion;
          final displayName = bibleVersionDisplayName(code);
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              widget.onChangeVersion?.call(code);
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check, color: context.accentInk(AppTheme.brandPurple), size: 20),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// An action in the reference row — edit, or the ⋮ menu.
///
/// Drawn as a 16pt glyph, as before, but answering a touch anywhere in a 44pt
/// square: the glyph plus 4pt of padding was a 24pt target, and on a phone the
/// pencil and the × that sat beside it were easy to miss or to hit the wrong
/// one.
class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      // The Semantics below already names the button; the tooltip's copy of
      // the same words made a screen reader say them twice.
      excludeFromSemantics: true,
      child: TapTarget(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: tooltip,
          onTap: onTap,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 16,
              color: context.accentInk(AppTheme.brandPurple),
            ),
          ),
        ),
      ),
    );
  }
}
