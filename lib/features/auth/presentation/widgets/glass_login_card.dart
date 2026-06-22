import 'package:flutter/material.dart';

/// Glass-style card with translucent fill and subtle border.
///
/// No BackdropFilter — uses a semi-transparent fill instead for much
/// better performance while retaining the frosted-glass look on dark backgrounds.
class GlassLoginCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassLoginCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
