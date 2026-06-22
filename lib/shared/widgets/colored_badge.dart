import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A small pill-shaped badge with a colored border, background, and label.
/// Used for tags, conditions, and other categorical chips.
class ColoredBadge extends StatelessWidget {
  final String label;
  final Color color;

  const ColoredBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppTheme.tagPadding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppTheme.alphaSubtle + 0.01),
        borderRadius: AppTheme.borderRadiusSM,
        border: Border.all(
          color: color.withValues(alpha: AppTheme.alphaMedStrong),
          width: AppTheme.borderWidthThin,
        ),
      ),
      child: Text(
        label,
        style: AppTheme.tiny.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
