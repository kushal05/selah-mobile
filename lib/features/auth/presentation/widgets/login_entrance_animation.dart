import 'package:flutter/material.dart';

/// Orchestrates the sequential entrance animation for the login screen.
///
/// Sequence: background fade -> logo scale -> title fade -> form slide -> button pop.
/// Duration: 500-700ms per element, 100ms delay between elements.
class LoginEntranceAnimation {
  final TickerProvider vsync;

  late final AnimationController _controller;

  late final Animation<double> backgroundFade;
  late final Animation<double> logoScale;
  late final Animation<double> titleFade;
  late final Animation<Offset> formSlide;
  late final Animation<double> formFade;
  late final Animation<double> buttonScale;
  late final Animation<double> buttonFade;

  static const _totalDuration = Duration(milliseconds: 2000);

  LoginEntranceAnimation({required this.vsync}) {
    _controller = AnimationController(
      vsync: vsync,
      duration: _totalDuration,
    );

    // Background: 0-500ms (0.0 - 0.25)
    backgroundFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
      ),
    );

    // Logo: 100-700ms (0.05 - 0.35)
    logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.05, 0.35, curve: Curves.easeOutBack),
      ),
    );

    // Title: 200-800ms (0.10 - 0.40)
    titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.10, 0.40, curve: Curves.easeOut),
      ),
    );

    // Form slide + fade: 400-1100ms (0.20 - 0.55)
    formSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.20, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    formFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.20, 0.50, curve: Curves.easeOut),
      ),
    );

    // Button pop: 500-1200ms (0.25 - 0.60)
    buttonScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.60, curve: Curves.easeOutBack),
      ),
    );
    buttonFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.25, 0.55, curve: Curves.easeOut),
      ),
    );
  }

  AnimationController get controller => _controller;

  void forward() => _controller.forward();

  void dispose() => _controller.dispose();
}
