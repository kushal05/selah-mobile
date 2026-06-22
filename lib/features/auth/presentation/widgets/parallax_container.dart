import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Provides subtle parallax depth effect based on pointer/gyro position.
///
/// Layers move at different speeds to create depth:
/// - background: 2px
/// - particles: 4px
/// - logo: 6px
/// - card: 3px
class ParallaxContainer extends StatefulWidget {
  final Widget child;

  const ParallaxContainer({super.key, required this.child});

  @override
  State<ParallaxContainer> createState() => ParallaxContainerState();
}

class ParallaxContainerState extends State<ParallaxContainer> {
  Offset _offset = Offset.zero;

  /// Current normalized offset for child widgets to read.
  Offset get offset => _offset;

  void _onPointerMove(PointerEvent event) {
    if (!mounted) return;
    final size = context.size;
    if (size == null) return;

    // Normalize to -1..1 range from center
    final dx = (event.localPosition.dx / size.width - 0.5) * 2;
    final dy = (event.localPosition.dy / size.height - 0.5) * 2;

    setState(() {
      _offset = Offset(dx, dy);
    });
  }

  void _onPointerExit(PointerExitEvent event) {
    // Smoothly return to center would need animation,
    // but for simplicity just reset
    setState(() => _offset = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerMove: _onPointerMove,
      onPointerUp: (_) => setState(() => _offset = Offset.zero),
      child: MouseRegion(
        onExit: _onPointerExit,
        child: widget.child,
      ),
    );
  }
}

/// Applies parallax offset to a child based on [ParallaxContainerState].
class ParallaxLayer extends StatelessWidget {
  final double magnitude;
  final Widget child;
  final Offset offset;

  const ParallaxLayer({
    super.key,
    required this.magnitude,
    required this.child,
    this.offset = Offset.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(offset.dx * magnitude, offset.dy * magnitude),
      child: child,
    );
  }
}
