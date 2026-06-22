import 'package:flutter/material.dart';

/// Touch interaction layer that creates expanding ripples on tap.
///
/// Ripple: radius 0->200px, opacity 0.4->0, duration 700ms.
class TouchRippleLayer extends StatefulWidget {
  final Widget child;

  const TouchRippleLayer({super.key, required this.child});

  @override
  State<TouchRippleLayer> createState() => _TouchRippleLayerState();
}

class _TouchRippleLayerState extends State<TouchRippleLayer> {
  final List<_RippleData> _ripples = [];

  void _addRipple(Offset position) {
    if (MediaQuery.of(context).disableAnimations) return;

    setState(() {
      _ripples.add(_RippleData(position: position));
    });
  }

  void _removeRipple(_RippleData ripple) {
    if (mounted) {
      setState(() => _ripples.remove(ripple));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) => _addRipple(details.localPosition),
      child: Stack(
        children: [
          widget.child,
          ...List.from(_ripples).map((ripple) => _RippleWidget(
                key: ValueKey(ripple),
                data: ripple,
                onComplete: () => _removeRipple(ripple),
              )),
        ],
      ),
    );
  }
}

class _RippleData {
  final Offset position;
  _RippleData({required this.position});
}

class _RippleWidget extends StatefulWidget {
  final _RippleData data;
  final VoidCallback onComplete;

  const _RippleWidget({
    super.key,
    required this.data,
    required this.onComplete,
  });

  @override
  State<_RippleWidget> createState() => _RippleWidgetState();
}

class _RippleWidgetState extends State<_RippleWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final radius = t * 200;
        final opacity = 0.4 * (1 - t);

        return Positioned(
          left: widget.data.position.dx - radius,
          top: widget.data.position.dy - radius,
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: opacity),
                width: 1.5,
              ),
            ),
          ),
        );
      },
    );
  }
}
