import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/motion_preferences.dart';

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
    final brightness = Theme.of(context).brightness;
    final bgColor = AppTheme.tintBackground(
        widget.color, 0.84, brightness == Brightness.dark);

    return Semantics(
      button: true,
      // The visible label can wrap or truncate; the accessible name never does.
      label: widget.label,
      excludeSemantics: true,
      // onTap must live on this node: excludeSemantics drops the child's
      // tap action, so without it the control announces as a button but
      // cannot be activated — the exact bug the onTapUp fix removed.
      onTap: () => widget.onTap(context),
      child: _build(context, bgColor),
    );
  }

  Widget _build(BuildContext context, Color bgColor) {
    final brightness = Theme.of(context).brightness;
    return GestureDetector(
      // The action lives on onTap, not onTapUp: only onTap contributes a tap
      // action to the semantics tree, so an onTapUp-only control is inert to
      // TalkBack and VoiceOver. onTapUp still resets the press animation.
      onTap: () => widget.onTap(context),
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? context.pressScale(AppTheme.pressedScaleSmall) : 1.0,
        duration: context.motion(AppTheme.durationFast),
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
                child: Icon(widget.icon,
                    size: AppTheme.iconLG,
                    color: AppTheme.accentOnTintFor(widget.color, brightness)),
              ),
              const SizedBox(height: AppTheme.spacing8),
              Text(
                widget.label,
                style: AppTheme.tiny.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkOnTintFor(widget.color, brightness),
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
