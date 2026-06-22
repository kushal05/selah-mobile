import 'package:flutter/material.dart';

/// Shape of the spotlight cutout around the target widget.
enum TutorialSpotlightShape {
  /// Rounded rectangle cutout.
  roundedRect,

  /// Circle cutout.
  circle,

  /// No spotlight — the scrim covers the full screen.
  none,
}

/// Where the coach mark bubble appears relative to the spotlight.
enum TutorialTooltipSide {
  /// Bubble is placed above the spotlight.
  above,

  /// Bubble is placed below the spotlight.
  below,

  /// Bubble is vertically centred — used when there is no target.
  center,
}

/// A single step in a tutorial sequence.
class TutorialStep {
  /// Key of the widget to spotlight. Null means no spotlight (full scrim).
  final GlobalKey? targetKey;

  final String title;
  final String description;

  final TutorialSpotlightShape shape;
  final TutorialTooltipSide tooltipSide;

  /// Extra padding added around the target widget's bounds for the spotlight.
  final EdgeInsets spotlightPadding;

  /// Optional icon shown in the coach mark header.
  final IconData? icon;

  const TutorialStep({
    this.targetKey,
    required this.title,
    required this.description,
    this.shape = TutorialSpotlightShape.roundedRect,
    this.tooltipSide = TutorialTooltipSide.above,
    this.spotlightPadding = const EdgeInsets.all(8),
    this.icon,
  });
}
