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

/// Every tag, A to Z, to tick any number of.
///
/// A search box, fixed at the top while the list scrolls under it, narrows the
/// list as you type. Searching for a name that does not exist offers to create
/// it, when [onCreate] is given; places that only choose among existing tags,
/// like filters, leave it null.
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
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();

  /// Makes the tag, ticks it, and lists it.
  Future<void> _create(String name) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final created = await widget.onCreate!(name);
      if (!mounted) return;
      if (created != null) {
        if (!_options.any((o) => o.id == created.id)) _options.add(created);
        _selected.add(created.id);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createFromSearch() async {
    final name = _query;
    if (name.isEmpty) return;
    await _create(name);
    if (mounted) _search.clear();
  }

  void _toggle(TagOption option, bool on) => setState(() {
        if (on) {
          _selected.add(option.id);
        } else {
          _selected.remove(option.id);
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = l10n(context);
    final theme = Theme.of(context);
    final accent = context.accentInk(widget.accent);
    final tint = widget.accent.withValues(alpha: AppTheme.alphaLightMed);

    final query = _query.toLowerCase();
    final searching = query.isNotEmpty;
    final matches = [
      for (final o in sortedTagOptions(_options))
        if (!searching || o.label.toLowerCase().contains(query)) o,
    ];
    final canCreateFromSearch = widget.onCreate != null &&
        searching &&
        !_options.any((o) => o.label.toLowerCase() == query);

    // Letter headings between groups, except while searching, where the result
    // is a short flat list.
    final rows = <Object>[];
    String? letter;
    for (final o in matches) {
      final first = o.label.isEmpty ? '#' : o.label.characters.first.toUpperCase();
      final heading = RegExp(r'\p{L}', unicode: true).hasMatch(first) ? first : '#';
      if (!searching && heading != letter) {
        rows.add(heading);
        letter = heading;
      }
      rows.add(o);
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: context.cardSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.sell_outlined, size: 22, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.tags, style: AppTheme.headingMedium),
                        Text(
                          t.tagsSelectedCount(_selected.length),
                          style: AppTheme.caption.copyWith(
                            color: _selected.isEmpty
                                ? context.mutedText
                                : accent,
                            fontWeight: _selected.isEmpty
                                ? FontWeight.w400
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t.close,
                    icon: Icon(Icons.close, color: context.mutedText),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ── Search (also how a new tag is made) ───────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                key: const Key('tag-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.onCreate != null ? t.searchOrCreateTag : t.searchTags,
                  isDense: true,
                  filled: true,
                  fillColor: context.subtleFill,
                  prefixIcon: Icon(Icons.search,
                      size: AppTheme.iconBase, color: context.hintText),
                  suffixIcon: searching
                      ? IconButton(
                          tooltip: t.clearSearch,
                          icon: Icon(Icons.cancel,
                              size: 18, color: context.hintText),
                          onPressed: _search.clear,
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                ),
              ),
            ),

            Divider(height: 1, color: context.hairline),

            // ── List ──────────────────────────────────────────────────
            Flexible(
              child: _options.isEmpty && !canCreateFromSearch
                  ? _EmptyState(
                      icon: Icons.sell_outlined,
                      text: widget.onCreate != null
                          ? t.noTagsYetCreate
                          : t.noTagsYet,
                    )
                  : (rows.isEmpty && !canCreateFromSearch)
                      ? _EmptyState(
                          icon: Icons.search_off,
                          text: t.noTagsMatch(_query),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          itemCount: rows.length + (canCreateFromSearch ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (canCreateFromSearch) {
                              if (i == 0) {
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  leading: Icon(Icons.add_circle_outline,
                                      color: accent),
                                  title: Text(
                                    t.createTagNamed(_query),
                                    style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  onTap: _busy ? null : _createFromSearch,
                                );
                              }
                              i -= 1;
                            }
                            final row = rows[i];
                            if (row is String) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 2),
                                child: Text(
                                  row,
                                  style: AppTheme.caption.copyWith(
                                    color: context.mutedText,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              );
                            }
                            final option = row as TagOption;
                            final on = _selected.contains(option.id);
                            return CheckboxListTile(
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              tileColor: on ? tint : null,
                              activeColor:
                                  AppTheme.accentSurface(widget.accent),
                              checkboxShape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5)),
                              value: on,
                              title: Text(
                                option.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight:
                                      on ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                              onChanged: (v) => _toggle(option, v ?? false),
                            );
                          },
                        ),
            ),

            // ── Footer ────────────────────────────────────────────────
            Divider(height: 1, color: context.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              // A Wrap, not a Row: at a large text size on a narrow phone the
              // two buttons do not fit side by side, and should stack rather
              // than run off the edge.
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t.actionCancel),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentSurface(widget.accent),
                      foregroundColor:
                          AppTheme.onAccent(AppTheme.accentSurface(widget.accent)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: context.hintText),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.mutedText),
          ),
        ],
      ),
    );
  }
}
