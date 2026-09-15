import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../l10n/l10n.dart';
import '../drag_handle.dart';

/// Search-and-select sheet for linking one record to another.
///
/// Previously an [AlertDialog] of bare [CheckboxListTile]s: a boxed-in list
/// with no room to read, an unstyled search field, and a "Link (2)" text
/// button that looked the same enabled or disabled. Everywhere else in the
/// app a choice like this is made in a sheet, so this is one too — full
/// height to read in, the app's own row treatment, and a filled primary
/// button that says what will happen.
///
/// [T] is the item type; [alreadyLinkedIds] are hidden, since linking
/// something twice is not a thing the user can want.
///
/// Only [LinkPicker.show] is public. The widget itself is a sheet body — it
/// has no Dialog or Material of its own — so handing it to `showDialog`
/// throws at render. That is exactly what happened when this became a sheet
/// and one of its two call sites was left on the old API, so the shape is
/// now enforced rather than documented.
abstract final class LinkPicker {
  /// Shows the picker and returns the chosen ids, or null if dismissed.
  static Future<List<String>?> show<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required Set<String> alreadyLinkedIds,
    required String Function(T) getId,
    required String Function(T) getLabel,
    String? Function(T)? getSubtitle,
    IconData icon = Icons.bookmark_outline_rounded,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LinkPickerSheet<T>(
        title: title,
        items: items,
        alreadyLinkedIds: alreadyLinkedIds,
        getId: getId,
        getLabel: getLabel,
        getSubtitle: getSubtitle,
        icon: icon,
      ),
    );
  }
}

class _LinkPickerSheet<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final Set<String> alreadyLinkedIds;
  final String Function(T) getId;
  final String Function(T) getLabel;
  final String? Function(T)? getSubtitle;

  /// Leading glyph for each row. Defaults to a bookmark, which suits the
  /// promises this is used for.
  final IconData icon;

  const _LinkPickerSheet({
    super.key,
    required this.title,
    required this.items,
    required this.alreadyLinkedIds,
    required this.getId,
    required this.getLabel,
    this.getSubtitle,
    this.icon = Icons.bookmark_outline_rounded,
  });

  @override
  State<_LinkPickerSheet<T>> createState() => _LinkPickerSheetState<T>();
}

class _LinkPickerSheetState<T> extends State<_LinkPickerSheet<T>> {
  final _searchController = TextEditingController();
  final _selectedIds = <String>{};
  String _query = '';

  List<T> get _filteredItems {
    final available = widget.items
        .where((item) => !widget.alreadyLinkedIds.contains(widget.getId(item)))
        .toList();
    if (_query.isEmpty) return available;
    final lower = _query.toLowerCase();
    return available.where((item) {
      final label = widget.getLabel(item).toLowerCase();
      final subtitle = widget.getSubtitle?.call(item)?.toLowerCase() ?? '';
      return label.contains(lower) || subtitle.contains(lower);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = l10n(context);
    final theme = Theme.of(context);
    final filtered = _filteredItems;
    final accent = AppTheme.accentOnTintFor(
        AppTheme.rosePink, theme.brightness);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        // Keyed so a test can measure this box rather than one of the several
        // ConstrainedBoxes the app scaffolding puts above it.
        key: const ValueKey('linkPickerSheet'),
        // A ceiling, not a height. Tall enough to read several items without
        // scrolling the sheet itself, which the 400px dialog could not do —
        // but a two-item list should not get the same sheet as a fifty-item
        // one, which a fixed height gave it.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: strings.close,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: strings.search,
                  prefixIcon:
                      const Icon(Icons.search, size: AppTheme.iconBase),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            const SizedBox(height: 4),
            // Flexible, not Expanded: the list takes only the height it needs
            // up to the ceiling above, so the sheet ends just below the last
            // row instead of leaving dead space under a short list.
            Flexible(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _query.isEmpty
                              ? strings.nothingLeftToLink
                              : strings.noResultsFor(_query),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.mutedText),
                        ),
                      ),
                    )
                  : ListView.builder(
                      // Sizes to its rows so a short list shortens the sheet;
                      // the Flexible above still caps it at the ceiling.
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final id = widget.getId(item);
                        final selected = _selectedIds.contains(id);
                        final subtitle = widget.getSubtitle?.call(item);

                        return _PickerRow(
                          icon: widget.icon,
                          accent: accent,
                          label: widget.getLabel(item),
                          subtitle: subtitle,
                          selected: selected,
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedIds.remove(id);
                            } else {
                              _selectedIds.add(id);
                            }
                          }),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selectedIds.isEmpty
                        ? null
                        : () =>
                            Navigator.pop(context, _selectedIds.toList()),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    child: Text(_selectedIds.isEmpty
                        ? strings.selectItemsToLink
                        : strings.linkNItems(_selectedIds.length)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable row, built like the app's list rows rather than a
/// checkbox tile: a tinted glyph, the label, and selection shown by the row
/// itself instead of a control off to one side.
class _PickerRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PickerRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: selected
              ? accent.withValues(alpha: AppTheme.alphaLight)
              : Colors.transparent,
          borderRadius: AppTheme.borderRadius2XL,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppTheme.borderRadius2XL,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: AppTheme.iconBadgeSM,
                    height: AppTheme.iconBadgeSM,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: AppTheme.alphaLightMed),
                      borderRadius: AppTheme.borderRadiusLG,
                    ),
                    child: Icon(icon, size: AppTheme.iconLG, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.primaryText,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                color: context.mutedText),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? accent : context.hintText,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
