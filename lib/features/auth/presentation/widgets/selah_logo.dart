import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

/// Branded Selah logo using the app icon asset with optional wordmark.
///
/// Three sizes: [SelahLogoSize.small] (48px), [SelahLogoSize.medium] (64px),
/// [SelahLogoSize.large] (100px). Includes optional glow halo animation.
enum SelahLogoSize { small, medium, large }

class SelahLogo extends StatelessWidget {
  final SelahLogoSize size;
  final bool showWordmark;

  const SelahLogo({
    super.key,
    this.size = SelahLogoSize.medium,
    this.showWordmark = true,
  });

  double get _iconContainerSize => switch (size) {
        SelahLogoSize.small => 48,
        SelahLogoSize.medium => 64,
        SelahLogoSize.large => 100,
      };

  double get _borderRadius => switch (size) {
        SelahLogoSize.small => 14,
        SelahLogoSize.medium => 18,
        SelahLogoSize.large => 24,
      };

  double get _wordmarkSize => switch (size) {
        SelahLogoSize.small => 20,
        SelahLogoSize.medium => 28,
        SelahLogoSize.large => 36,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // App icon
        Container(
          width: _iconContainerSize,
          height: _iconContainerSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_borderRadius),
            boxShadow: AppTheme.shadowGlow(AppTheme.brandPurple),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_borderRadius),
            child: Image.asset(
              'assets/images/app_icon.png',
              width: _iconContainerSize,
              height: _iconContainerSize,
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (showWordmark) ...[
          SizedBox(height: size == SelahLogoSize.large ? AppTheme.spacing16 : AppTheme.spacing10),
          Text(
            'Selah',
            style: TextStyle(
              fontSize: _wordmarkSize,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Wraps [SelahLogo] with a pulsing glow halo.
///
/// Glow: scale 1→1.08, opacity 0.25→0.5, duration 3s, looping.
/// Call [startGlow] after entrance animation completes.
class SelahLogoGlow extends StatefulWidget {
  final SelahLogoSize size;
  final bool showWordmark;

  const SelahLogoGlow({
    super.key,
    this.size = SelahLogoSize.medium,
    this.showWordmark = true,
  });

  @override
  State<SelahLogoGlow> createState() => SelahLogoGlowState();
}

class SelahLogoGlowState extends State<SelahLogoGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacityAnim = Tween<double>(begin: 0.25, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  void startGlow() {
    if (MediaQuery.of(context).disableAnimations) return;
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _haloSize => switch (widget.size) {
        SelahLogoSize.small => 80,
        SelahLogoSize.medium => 110,
        SelahLogoSize.large => 160,
      };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _haloSize,
              height: _haloSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glow halo
                  Transform.scale(
                    scale: _scaleAnim.value,
                    child: Container(
                      width: _haloSize,
                      height: _haloSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppTheme.brandPurple
                                .withValues(alpha: _opacityAnim.value),
                            AppTheme.brandPurple.withValues(alpha: 0),
                          ],
                          stops: const [0.3, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Logo (without wordmark — we add it below the halo)
                  SelahLogo(size: widget.size, showWordmark: false),
                ],
              ),
            ),
            if (widget.showWordmark) ...[
              SizedBox(
                  height: widget.size == SelahLogoSize.large ? AppTheme.spacing16 : AppTheme.spacing10),
              Text(
                'Selah',
                style: TextStyle(
                  fontSize: switch (widget.size) {
                    SelahLogoSize.small => 20.0,
                    SelahLogoSize.medium => 28.0,
                    SelahLogoSize.large => 36.0,
                  },
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
