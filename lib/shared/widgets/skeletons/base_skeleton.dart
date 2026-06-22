import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A theme-aware skeleton placeholder with an animated shimmer pulse.
///
/// Used as the building block for all skeleton loading widgets.
class BaseSkeleton extends StatefulWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxShape shape;

  const BaseSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.shape = BoxShape.rectangle,
  });

  /// Circular skeleton (e.g. avatar placeholder).
  const BaseSkeleton.circle({
    super.key,
    required double size,
  })  : width = size,
        height = size,
        borderRadius = 0,
        shape = BoxShape.circle;

  @override
  State<BaseSkeleton> createState() => _BaseSkeletonState();
}

class _StandaloneTickerProvider implements TickerProvider {
  Ticker? _ticker;

  @override
  Ticker createTicker(TickerCallback onTick) {
    _ticker = Ticker(onTick);
    return _ticker!;
  }

  void dispose() {
    _ticker?.dispose();
  }
}

class _BaseSkeletonState extends State<BaseSkeleton> {
  late final Animation<double> _animation;

  // Shared static ticker so all skeletons pulse in sync.
  static final _syncNotifier = ValueNotifier<double>(0);
  static AnimationController? _sharedController;
  static _StandaloneTickerProvider? _tickerProvider;
  static int _refCount = 0;

  @override
  void initState() {
    super.initState();
    _refCount++;
    if (_sharedController == null) {
      _tickerProvider = _StandaloneTickerProvider();
      _sharedController = AnimationController(
        vsync: _tickerProvider!,
        duration: const Duration(milliseconds: 1500),
      )..repeat(reverse: true);
      _sharedController!.addListener(() {
        _syncNotifier.value = _sharedController!.value;
      });
    }
    _animation = Tween<double>(begin: 0.04, end: 0.12).animate(
      CurvedAnimation(parent: _sharedController!, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _refCount--;
    if (_refCount == 0) {
      _sharedController?.dispose();
      _sharedController = null;
      _tickerProvider = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.onSurface;

    return ValueListenableBuilder<double>(
      valueListenable: _syncNotifier,
      builder: (context, _, _) {
        final opacity = _animation.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: opacity),
            borderRadius: widget.shape == BoxShape.circle
                ? null
                : BorderRadius.circular(widget.borderRadius),
            shape: widget.shape,
          ),
        );
      },
    );
  }
}
