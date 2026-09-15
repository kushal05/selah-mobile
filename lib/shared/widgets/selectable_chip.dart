import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_colors.dart';

/// A chip the user turns on and off — a tag, a filter, a scale.
///
/// Four screens had their own, and each filled differently when selected:
/// two with `colorScheme.primary` behind white text (4.20:1 in dark, where
/// primary is a pale blue), one with a raw accent, one with a grey. This one
/// fills with [AppTheme.accentSurface], which is the accent darkened until a
/// white label clears 4.5:1 in either theme.
class SelectableChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// Shows a × on the selected chip, for chips that represent a value the
  /// user can take off again.
  final bool showDelete;

  final IconData? icon;

  /// The accent this chip belongs to — a tab's colour, usually.
  final Color accent;

  const SelectableChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.showDelete = false,
    this.icon,
    this.accent = AppTheme.brandBlue,
  });

  @override
  Widget build(BuildContext context) {
    final fill = AppTheme.accentSurface(accent);
    final fg = isSelected ? Colors.white : context.primaryText;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? fill : context.subtleFill,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppTheme.iconMD, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(fontSize: 15, color: fg),
                ),
                if (showDelete && isSelected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.close,
                      size: AppTheme.iconMD,
                      color: Colors.white.withValues(alpha: 0.85)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
