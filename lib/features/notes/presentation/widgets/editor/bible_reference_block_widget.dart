import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../bible/domain/models/bible_reference.dart';
import '../../../../bible/domain/models/bible_version_info.dart';

/// Renders a Bible verse block in the note editor as a collapsible card.
///
/// Collapsed: shows only the reference line (e.g. "John 3:16 (KJV)").
/// Expanded:  shows the reference line plus the verse text.
/// Tap toggles expand/collapse. Long-press opens the options sheet.
class BibleReferenceBlockWidget extends StatefulWidget {
  final BibleReference reference;
  final VoidCallback? onRemove;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onChangeVersion;
  final VoidCallback? onTap;

  /// Available translations from the Bible DB, used by the version picker.
  final List<String> availableTranslations;

  const BibleReferenceBlockWidget({
    super.key,
    required this.reference,
    this.onRemove,
    this.onEdit,
    this.onChangeVersion,
    this.onTap,
    this.availableTranslations = const [],
  });

  @override
  State<BibleReferenceBlockWidget> createState() =>
      _BibleReferenceBlockWidgetState();
}

class _BibleReferenceBlockWidgetState extends State<BibleReferenceBlockWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
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
    super.dispose();
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

    return GestureDetector(
      onTap: widget.onTap ?? (hasText ? _toggle : null),
      onLongPress: () => _showOptions(context),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.brandPurple.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.brandPurple.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            crossAxisAlignment:
                _expanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              // Bookmark icon
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.brandPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.menu_book,
                  size: 18,
                  color: AppTheme.brandPurple,
                ),
              ),
              const SizedBox(width: 12),
              // Reference content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reference line (e.g., "John 3:16-18")
                    Text(
                      ref.displayReference,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.brandPurple,
                        letterSpacing: 0.2,
                      ),
                    ),
                    // Verse text — only visible when expanded
                    if (_expanded) ...[
                      const SizedBox(height: 6),
                      if (ref.pending || ref.text.isEmpty)
                        Text(
                          'Verse text pending download...',
                          style: TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade500,
                            height: 1.5,
                          ),
                        )
                      else
                        _buildVerseText(theme),
                    ],
                  ],
                ),
              ),
              // Action icons + chevron
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onEdit != null)
                    _ActionIcon(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit Reference',
                      onTap: widget.onEdit!,
                    ),
                  if (widget.onRemove != null)
                    _ActionIcon(
                      icon: Icons.close,
                      tooltip: 'Remove Reference',
                      onTap: widget.onRemove!,
                      color: Colors.red.shade400,
                    ),
                  if (hasText)
                    RotationTransition(
                      turns: Tween(begin: 0.0, end: 0.5).animate(
                        CurvedAnimation(
                          parent: _iconController,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: Icon(
                        Icons.expand_more,
                        size: 20,
                        color: AppTheme.brandPurple.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build verse text with optional superscript verse numbers
  Widget _buildVerseText(ThemeData theme) {
    final ref = widget.reference;
    final baseColor =
        theme.textTheme.bodyMedium?.color ?? Colors.grey.shade700;
    final showNumbers =
        ref.display.showVerseNumbers && ref.text.length > 1;

    if (!showNumbers) {
      return Text(
        ref.fullText,
        style: TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          color: baseColor,
          height: 1.5,
        ),
      );
    }

    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 14,
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
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.normal,
                  color: AppTheme.brandPurple.withValues(alpha: 0.7),
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
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
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
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy Verse Text'),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.reference.fullText));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Verse text copied'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: const Text('Copy Reference'),
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.reference.displayReference));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reference copied'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              if (widget.onEdit != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit Reference'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onEdit?.call();
                  },
                ),
              if (widget.onChangeVersion != null)
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: const Text('Change Version'),
                  onTap: () {
                    Navigator.pop(context);
                    _showVersionPicker(context);
                  },
                ),
              if (widget.onRemove != null)
                ListTile(
                  leading: Icon(Icons.delete_outline,
                      color: Colors.red.shade400),
                  title: Text('Remove Reference',
                      style: TextStyle(color: Colors.red.shade400)),
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
        title: const Text('Select Version'),
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
                  const Icon(Icons.check, color: AppTheme.brandPurple, size: 20),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: color ?? AppTheme.brandPurple.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
