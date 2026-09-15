import 'package:flutter/material.dart';

/// Motion preferences.
///
/// Reduce Motion is enabled because motion causes nausea, dizziness or
/// migraine — not because someone dislikes animation. Honouring it on some
/// screens and not others therefore provides no protection at all: the app
/// previously respected it in the five auth widgets and ignored it in the
/// sixteen other files that animate.
///
/// Read it through [MotionContext] at the call site — it comes from
/// MediaQuery, so no provider or scope widget is needed.
/// Motion helpers for any widget with a [BuildContext].
extension MotionContext on BuildContext {
  /// True when the OS Reduce Motion setting is on.
  bool get reduceMotion => MediaQuery.of(this).disableAnimations;

  /// [duration], or [Duration.zero] when Reduce Motion is on.
  ///
  /// Collapsing to zero rather than skipping the widget keeps the end state
  /// identical — the transition simply happens instantly, so nothing that
  /// depends on the animation completing breaks.
  Duration motion(Duration duration) =>
      reduceMotion ? Duration.zero : duration;

  /// A curve safe to use under Reduce Motion. Overshooting curves
  /// (`easeOutBack`, `elasticOut`) read as bouncing even over a short
  /// duration, so they are flattened.
  Curve motionCurve(Curve curve) => reduceMotion ? Curves.linear : curve;

  /// Scale factor for a press effect: 1.0 (no scaling) under Reduce Motion.
  double pressScale(double scale) => reduceMotion ? 1.0 : scale;
}
