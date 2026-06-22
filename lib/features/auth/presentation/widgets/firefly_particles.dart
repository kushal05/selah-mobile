import 'dart:math';
import 'package:flutter/material.dart';

/// Subtle firefly particle system with slow upward drift and fade in/out.
///
/// 10 particles, no per-particle blur (uses simple circles with opacity).
class FireflyParticles extends StatefulWidget {
  const FireflyParticles({super.key});

  @override
  State<FireflyParticles> createState() => _FireflyParticlesState();
}

class _FireflyParticlesState extends State<FireflyParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Firefly> _fireflies;
  final _random = Random();
  double _lastT = 0;

  @override
  void initState() {
    super.initState();
    _fireflies = List.generate(10, (_) => _Firefly.random(_random));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_tick);
    _controller.repeat();
  }

  void _tick() {
    final now = _controller.lastElapsedDuration?.inMicroseconds ?? 0;
    final dt = (now - _lastT) / 1e6;
    _lastT = now.toDouble();
    if (dt <= 0 || dt > 0.5) return;

    for (final f in _fireflies) {
      f.y -= f.speed * dt * 60;
      f.x += sin(f.swayPhase + f.lifePhase) * f.swayAmplitude * dt * 6;
      f.lifePhase += dt * 1.2;

      if (f.y < -0.05) f.reset(_random);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return const SizedBox.expand();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _FireflyPainter(_fireflies),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Firefly {
  double x;
  double y;
  double size;
  double opacity;
  double speed;
  double swayPhase;
  double swayAmplitude;
  double lifePhase;

  _Firefly({
    required this.x,
    required this.y,
    required this.size,
    required this.opacity,
    required this.speed,
    required this.swayPhase,
    required this.swayAmplitude,
    required this.lifePhase,
  });

  factory _Firefly.random(Random r) {
    return _Firefly(
      x: r.nextDouble(),
      y: r.nextDouble(),
      size: 2.0 + r.nextDouble() * 2.5,
      opacity: 0.2 + r.nextDouble() * 0.4,
      speed: 0.0002 + r.nextDouble() * 0.0004,
      swayPhase: r.nextDouble() * 2 * pi,
      swayAmplitude: 0.002 + r.nextDouble() * 0.005,
      lifePhase: r.nextDouble() * 2 * pi,
    );
  }

  void reset(Random r) {
    x = r.nextDouble();
    y = 1.0 + r.nextDouble() * 0.1;
    size = 2.0 + r.nextDouble() * 2.5;
    opacity = 0.2 + r.nextDouble() * 0.4;
    speed = 0.0002 + r.nextDouble() * 0.0004;
    swayPhase = r.nextDouble() * 2 * pi;
    swayAmplitude = 0.002 + r.nextDouble() * 0.005;
    lifePhase = 0;
  }
}

class _FireflyPainter extends CustomPainter {
  final List<_Firefly> fireflies;

  _FireflyPainter(this.fireflies);

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in fireflies) {
      final pulse = (sin(f.lifePhase * 1.5) + 1) / 2;
      final alpha = f.opacity * pulse;

      if (alpha < 0.05) continue;

      // Simple circle with no blur filter — much cheaper than MaskFilter
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha.clamp(0.0, 0.6));

      canvas.drawCircle(
        Offset(f.x * size.width, f.y * size.height),
        f.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FireflyPainter oldDelegate) => true;
}
