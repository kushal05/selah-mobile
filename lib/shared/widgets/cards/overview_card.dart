import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

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
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? AppTheme.pressedScale : 1.0,
        duration: AppTheme.durationFast,
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            gradient: AppTheme.cardGradient(widget.color),
            borderRadius: AppTheme.borderRadius4XL,
            boxShadow: AppTheme.coloredCardShadow(widget.color),
          ),
          child: Stack(
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
                  children: [
                    // Icon badge
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacing10),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: AppTheme.alphaMedLight),
                        borderRadius: AppTheme.borderRadiusXL,
                      ),
                      child: Icon(widget.icon, size: AppTheme.iconLG, color: widget.color),
                    ),
                    // Count + title
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.count,
                          style: AppTheme.displayLarge.copyWith(
                            color: widget.color.withValues(alpha: AppTheme.alphaNearlySolid),
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        Text(
                          widget.title,
                          style: AppTheme.caption.copyWith(
                            color: widget.color.withValues(alpha: AppTheme.alphaText),
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
