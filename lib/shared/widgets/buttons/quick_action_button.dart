import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A reusable quick action button with an icon and label.
/// Includes a press scale animation for premium tactile feedback.
class QuickActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final void Function(BuildContext) onTap;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<QuickActionButton> createState() => _QuickActionButtonState();
}

class _QuickActionButtonState extends State<QuickActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = AppTheme.tintBackground(widget.color);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap(context);
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? AppTheme.pressedScaleSmall : 1.0,
        duration: AppTheme.durationFast,
        child: Container(
          width: AppTheme.quickActionWidth,
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing8, vertical: AppTheme.spacing14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: AppTheme.borderRadius3XL,
            boxShadow: AppTheme.shadowMD(widget.color),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing11),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: AppTheme.alphaMedium),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: AppTheme.iconLG, color: widget.color),
              ),
              const SizedBox(height: AppTheme.spacing8),
              Text(
                widget.label,
                style: AppTheme.tiny.copyWith(
                  fontWeight: FontWeight.w600,
                  color: widget.color.withValues(alpha: AppTheme.alphaTextStrong),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
