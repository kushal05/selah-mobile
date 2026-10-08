import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_colors.dart';
import 'selah_sheet.dart';

/// One choice in a [showListSheet].
///
/// [value] cannot be null: the sheet returns null when dismissed, so a null
/// choice ("No folder") would be indistinguishable from backing out. Give it a
/// value of its own — an empty string, a sentinel — instead.
class SheetListItem<T extends Object> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;

  const SheetListItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
  });
}

/// Asks the person to pick one of [items]. Returns its value, or null if the
/// sheet was dismissed.
///
/// Choosing closes the sheet: there is no OK to press after the choice, which
/// the dialog pickers needed. [selected] marks the current choice. A long list
/// scrolls inside a sheet held to 85% of the screen, the header staying put.
Future<T?> showListSheet<T extends Object>(
  BuildContext context, {
  required String title,
  required List<SheetListItem<T>> items,
  String? subtitle,
  IconData? icon,
  Color accent = AppTheme.brandBlue,
  T? selected,
}) {
  return showSelahSheet<T>(
    context,
    builder: (sheetContext) => SelahSheet(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accent,
      expandBody: true,
      body: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        itemBuilder: (context, i) => _Row(
          item: items[i],
          selected: items[i].value == selected,
          accent: accent,
          onTap: () => Navigator.of(sheetContext).pop(items[i].value),
        ),
      ),
    ),
  );
}

class _Row<T extends Object> extends StatelessWidget {
  final SheetListItem<T> item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Row({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = context.accentInk(accent);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.borderRadiusLG,
        child: ConstrainedBox(
          // Comfortably over the 44pt floor: these are the whole point of the
          // sheet and are tapped one-handed.
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon,
                      size: AppTheme.iconLG,
                      color: selected ? ink : context.mutedText),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? ink : context.primaryText,
                        ),
                      ),
                      if (item.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!,
                          style:
                              TextStyle(fontSize: 13, color: context.mutedText),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, color: ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
