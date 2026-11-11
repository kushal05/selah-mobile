import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../l10n/l10n.dart';

/// A tag as the picker sees it: whatever the screen identifies it by, and what
/// to call it. Screens that keep tags by id pass the id; screens that keep
/// plain names pass the name for both.
@immutable
class TagOption {
  final String id;
  final String label;

  const TagOption(this.id, this.label);
}

/// [options] A to Z by label, ignoring case.
List<TagOption> sortedTagOptions(Iterable<TagOption> options) =>
    options.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

/// Every tag, A to Z, to tick any number of. "Add tag" stays fixed at the top
/// while the list scrolls under it (and is left out when [onCreate] is null,
/// for places that only choose among existing tags, like filters).
///
/// Returns the ticked ids on Done, or null if dismissed.
class TagPickerDialog extends StatefulWidget {
  final List<TagOption> options;
  final Set<String> selected;

  /// Creates a tag from the typed name and returns it, or null to add nothing.
  /// The new tag is ticked.
  final Future<TagOption?> Function(String name)? onCreate;

  final Color accent;

  const TagPickerDialog({
    super.key,
    required this.options,
    required this.selected,
    this.onCreate,
    this.accent = AppTheme.brandBlue,
  });

  static Future<Set<String>?> show(
    BuildContext context, {
    required List<TagOption> options,
    required Set<String> selected,
    Future<TagOption?> Function(String name)? onCreate,
    Color accent = AppTheme.brandBlue,
  }) {
    return showDialog<Set<String>>(
      context: context,
      builder: (_) => TagPickerDialog(
        options: options,
        selected: selected,
        onCreate: onCreate,
        accent: accent,
      ),
    );
  }

  @override
  State<TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<TagPickerDialog> {
  late final List<TagOption> _options = [...widget.options];
  late final Set<String> _selected = {...widget.selected};
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _adding = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startAdding() {
    setState(() => _adding = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _stopAdding() {
    _controller.clear();
    setState(() => _adding = false);
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _busy) {
      _stopAdding();
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await widget.onCreate!(name);
      if (!mounted) return;
      if (created != null) {
        if (!_options.any((o) => o.id == created.id)) _options.add(created);
        _selected.add(created.id);
      }
    } finally {
      if (mounted) {
        _busy = false;
        _stopAdding();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = l10n(context);
    final accent = context.accentInk(widget.accent);
    final sorted = sortedTagOptions(_options);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(t.tags, style: AppTheme.headingMedium),
            ),
            // Fixed: outside the scrolling list below.
            if (widget.onCreate != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _adding
                    ? Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                hintText: t.enterTagName,
                                isDense: true,
                                border: InputBorder.none,
                                prefixIcon: Icon(Icons.label_outline,
                                    size: AppTheme.iconBase,
                                    color: context.hintText),
                              ),
                              onSubmitted: (_) => _submit(),
                            ),
                          ),
                          IconButton(
                            tooltip: t.addTag,
                            icon: Icon(Icons.check, color: accent),
                            onPressed: _submit,
                          ),
                          IconButton(
                            tooltip: t.actionCancel,
                            icon: Icon(Icons.close, color: context.mutedText),
                            onPressed: _stopAdding,
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _startAdding,
                          style: TextButton.styleFrom(foregroundColor: accent),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(t.addTag),
                        ),
                      ),
              ),
            const Divider(height: 1),
            Flexible(
              child: sorted.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(t.noTagsYet,
                            style: TextStyle(color: context.mutedText)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: sorted.length,
                      itemBuilder: (context, i) {
                        final option = sorted[i];
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppTheme.accentSurface(widget.accent),
                          value: _selected.contains(option.id),
                          title: Text(option.label),
                          onChanged: (on) => setState(() {
                            if (on ?? false) {
                              _selected.add(option.id);
                            } else {
                              _selected.remove(option.id);
                            }
                          }),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.actionCancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_selected),
                    child: Text(t.done),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
