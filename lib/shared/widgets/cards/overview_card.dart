import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/motion_preferences.dart';

/// A reusable overview card displaying an icon, count, and title.
/// Used in dashboard grids to show summary statistics.
/// Includes a press scale animation for premium tactile feedback.
class OverviewCard extends StatefulWidget {
  final String title;
  final String count;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const OverviewCard({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  State<OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<OverviewCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // The count and title are two Text nodes, so a screen reader would read
    // them as unrelated fragments — "12", "Active Prayers". Merging them into
    // one labelled button makes the card a single meaningful stop.
    return Semantics(
      button: true,
      label: '${widget.count} ${widget.title}',
      excludeSemantics: true,
      // onTap must live on this node: excludeSemantics drops the child's
      // tap action, so without it the control announces as a button but
      // cannot be activated — the exact bug the onTapUp fix removed.
      onTap: widget.onTap,
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return GestureDetector(
      // The action lives on onTap, not onTapUp: only onTap contributes a tap
      // action to the semantics tree, so an onTapUp-only control is inert to
      // TalkBack and VoiceOver. onTapUp still resets the press animation.
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? context.pressScale(AppTheme.pressedScale) : 1.0,
        duration: context.motion(AppTheme.durationFast),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: AppTheme.cardGradient(widget.color,
                dark: brightness == Brightness.dark),
            borderRadius: AppTheme.borderRadius4XL,
            boxShadow: AppTheme.coloredCardShadow(widget.color),
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // Decorative background circles
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: AppTheme.alphaLight),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  width: AppTheme.iconBadgeMD,
                  height: AppTheme.iconBadgeMD,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: AppTheme.alphaSubtle),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: AppTheme.paddingAllBase,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon badge
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacing10),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: AppTheme.alphaMedLight),
                        borderRadius: AppTheme.borderRadiusXL,
                      ),
                      child: Icon(widget.icon,
                          size: AppTheme.iconLG,
                          color: AppTheme.accentOnTintFor(
                              widget.color, brightness)),
                    ),
                    // Count + title
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.count,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // Same colour as the card's icon, so the number
                          // and the glyph above it read as one object. At
                          // 32px/w800 this is WCAG "large text" (3:1), which
                          // the icon accent clears on every card tint.
                          style: AppTheme.displayLarge.copyWith(
                            color: AppTheme.accentOnTintFor(
                                widget.color, brightness),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.inkOnTintMutedFor(
                                widget.color, brightness),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
