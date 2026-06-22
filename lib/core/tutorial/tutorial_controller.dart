import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tutorial_overlay_widget.dart';
import 'tutorial_providers.dart';
import 'tutorial_state.dart';
import 'tutorial_step.dart';

/// Manages the tutorial [OverlayEntry] lifecycle and step progression.
///
/// Obtain via [tutorialControllerProvider]:
/// ```dart
/// ref.read(tutorialControllerProvider).start(context, steps);
/// ```
class TutorialController {
  OverlayEntry? _entry;
  final Ref _ref;

  TutorialController(this._ref);

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Inserts the tutorial overlay and begins at step 0.
  ///
  /// [steps] is the ordered list of [TutorialStep]s to walk through.
  void start(BuildContext context, List<TutorialStep> steps) {
    if (steps.isEmpty) return;

    // Remove any in-progress overlay before starting a new one.
    _entry?.remove();
    _entry = null;

    _ref.read(tutorialStateProvider.notifier).state = TutorialState(
      stepIndex: 0,
      totalSteps: steps.length,
    );

    _entry = OverlayEntry(
      builder: (_) => TutorialOverlayWidget(
        steps: steps,
        onNext: next,
        onSkip: skip,
      ),
    );

    // rootOverlay: true ensures the entry sits above all routes / dialogs.
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  /// Advances to the next step, or completes the tutorial if on the last step.
  void next() {
    final state = _ref.read(tutorialStateProvider);
    if (state.stepIndex + 1 < state.totalSteps) {
      _ref.read(tutorialStateProvider.notifier).state =
          state.copyWith(stepIndex: state.stepIndex + 1);
    } else {
      _complete();
    }
  }

  /// Dismisses the tutorial immediately.
  void skip() => _complete();

  // ── Private ─────────────────────────────────────────────────────────────────

  void _complete() {
    _entry?.remove();
    _entry = null;
    _ref.read(tutorialStateProvider.notifier).state =
        const TutorialState.inactive();
    unawaited(_ref.read(tutorialServiceProvider).markSeen());
  }
}

final tutorialControllerProvider = Provider<TutorialController>(
  (ref) => TutorialController(ref),
);
