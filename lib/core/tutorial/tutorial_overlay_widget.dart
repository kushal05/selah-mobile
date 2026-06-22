import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tutorial_providers.dart';
import 'tutorial_state.dart';
import 'tutorial_step.dart';

/// Full-screen overlay rendered via [OverlayEntry] during the tutorial.
///
/// Paints a semi-transparent scrim with a transparent spotlight around the
/// current step's target widget, then positions a [_CoachMarkBubble] above or
/// below the spotlight (or centred when there is no target).
class TutorialOverlayWidget extends ConsumerWidget {
  final List<TutorialStep> steps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const TutorialOverlayWidget({
    super.key,
    required this.steps,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tutorialStateProvider);

    if (!state.isActive || state.stepIndex >= steps.length) {
      return const SizedBox.shrink();
    }

    final step = steps[state.stepIndex];
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final padding = mq.padding;

    // Resolve the target widget's screen-space rect (null if not in tree).
    final targetRect = _resolveTargetRect(step);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // ── Scrim + spotlight hole ────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _SpotlightPainter(
                targetRect: targetRect,
                shape: step.shape,
              ),
            ),
          ),

          // For the final/celebration step tap the whole scrim to advance.
          if (step.shape == TutorialSpotlightShape.none)
            Positioned.fill(
              child: GestureDetector(
                onTap: onNext,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),

          // ── Coach mark bubble ─────────────────────────────────────────
          _positionedBubble(
            context: context,
            step: step,
            state: state,
            targetRect: targetRect,
            screen: screen,
            safeTop: padding.top,
            safeBottom: padding.bottom,
            onNext: onNext,
            onSkip: onSkip,
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static Rect? _resolveTargetRect(TutorialStep step) {
    if (step.targetKey == null) return null;
    final ctx = step.targetKey!.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;

    final pos = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      pos.dx - step.spotlightPadding.left,
      pos.dy - step.spotlightPadding.top,
      box.size.width + step.spotlightPadding.horizontal,
      box.size.height + step.spotlightPadding.vertical,
    );
  }

  static Widget _positionedBubble({
    required BuildContext context,
    required TutorialStep step,
    required TutorialState state,
    required Rect? targetRect,
    required Size screen,
    required double safeTop,
    required double safeBottom,
    required VoidCallback onNext,
    required VoidCallback onSkip,
  }) {
    const bubbleWidth = 300.0;
    const estimatedHeight = 210.0;
    const gap = 14.0;
    const margin = 16.0;

    final left = ((screen.width - bubbleWidth) / 2).clamp(margin, screen.width - bubbleWidth - margin);

    double top;

    if (step.tooltipSide == TutorialTooltipSide.center || targetRect == null) {
      top = (screen.height - estimatedHeight) / 2;
    } else if (step.tooltipSide == TutorialTooltipSide.above) {
      top = (targetRect.top - estimatedHeight - gap)
          .clamp(safeTop + margin, screen.height - estimatedHeight - safeBottom - margin);
    } else {
      top = (targetRect.bottom + gap)
          .clamp(safeTop + margin, screen.height - estimatedHeight - safeBottom - margin);
    }

    return Positioned(
      left: left,
      top: top,
      width: bubbleWidth,
      child: _CoachMarkBubble(
        step: step,
        stepIndex: state.stepIndex,
        totalSteps: state.totalSteps,
        onNext: onNext,
        onSkip: onSkip,
      ),
    );
  }
}

// ─── Coach mark bubble ────────────────────────────────────────────────────────

class _CoachMarkBubble extends StatelessWidget {
  final TutorialStep step;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _CoachMarkBubble({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = stepIndex == totalSteps - 1;

    return Material(
      borderRadius: BorderRadius.circular(16),
      elevation: 10,
      shadowColor: Colors.black45,
      color: theme.colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (step.icon != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      step.icon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    step.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _StepDots(current: stepIndex, total: totalSteps),
              ],
            ),

            const SizedBox(height: 10),

            Text(
              step.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                if (!isLast)
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor:
                          theme.colorScheme.onSurfaceVariant,
                    ),
                    child: const Text('Skip'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(isLast ? 'Get Started' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small progress dots shown in the coach mark header.
class _StepDots extends StatelessWidget {
  final int current;
  final int total;

  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final inactive = Theme.of(context).colorScheme.outlineVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: isActive ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? primary : inactive,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ─── Spotlight painter ────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final TutorialSpotlightShape shape;

  const _SpotlightPainter({required this.targetRect, required this.shape});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.68);

    if (targetRect == null || shape == TutorialSpotlightShape.none) {
      canvas.drawRect(Offset.zero & size, scrim);
      return;
    }

    final holePath = switch (shape) {
      TutorialSpotlightShape.circle => Path()..addOval(targetRect!),
      TutorialSpotlightShape.roundedRect => Path()
        ..addRRect(
            RRect.fromRectAndRadius(targetRect!, const Radius.circular(14))),
      // none is handled by the early return above; unreachable.
      _ => Path(),
    };

    // Scrim with hole.
    final scrimPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      holePath,
    );
    canvas.drawPath(scrimPath, scrim);

    // Subtle white border around the spotlight.
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(holePath, borderPaint);
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.targetRect != targetRect || old.shape != shape;
}
