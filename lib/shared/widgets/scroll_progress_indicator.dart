import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_colors.dart';

/// A short bar under a horizontally scrolling row, showing how much of it is
/// off screen and where you are in it.
///
/// Without one a row reads as complete: the tiles fill the width, the last is
/// a sliver at the edge, and nothing says the list continues — so people stop
/// at what they can see. The thumb's width is the visible fraction of the
/// content, so it also answers "how much more is there".
class ScrollProgressIndicator extends StatefulWidget {
  final ScrollController controller;

  /// Width of the track. The thumb travels its full length.
  final double width;

  /// Height the widget occupies including its padding, whether or not a bar
  /// is drawn — so a row that turns out to fit does not sit 15pt higher than
  /// one that does not.
  static const reservedHeight = 15.0;

  const ScrollProgressIndicator({
    super.key,
    required this.controller,
    this.width = 56.0,
  });

  @override
  State<ScrollProgressIndicator> createState() =>
      _ScrollProgressIndicatorState();
}

class _ScrollProgressIndicatorState extends State<ScrollProgressIndicator> {
  // The metrics the currently drawn bar was built from. We build before the
  // scroll view below us lays out, so what we read is always one frame stale:
  // empty on the first frame, and wrong again whenever the row's content
  // changes width (a text-size change re-flows the tiles). Comparing after
  // layout is what corrects both — the scroll listener only fires on a
  // scroll, which is the one moment the bar is no longer news.
  double? _builtMax;
  double? _builtViewport;
  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(ScrollProgressIndicator old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _scheduleMetricsCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted || !widget.controller.hasClients) return;
      final p = widget.controller.position;
      if (!p.hasContentDimensions || !p.hasViewportDimension) return;
      if (p.maxScrollExtent != _builtMax ||
          p.viewportDimension != _builtViewport) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMetricsCheck();

    // Reserve the height whether or not a bar is drawn, so a row that turns
    // out to fit does not sit higher than one that does not, and nothing
    // below shifts on the frame the bar appears.
    const placeholder =
        SizedBox(height: ScrollProgressIndicator.reservedHeight);

    if (!widget.controller.hasClients) return placeholder;
    final position = widget.controller.position;
    if (!position.hasContentDimensions || !position.hasViewportDimension) {
      return placeholder;
    }

    final maxExtent = position.maxScrollExtent;
    _builtMax = maxExtent;
    _builtViewport = position.viewportDimension;

    // Everything already fits. A bar that can never move is worse than no
    // bar: it claims there is somewhere to go.
    if (maxExtent <= 0 || !maxExtent.isFinite) return placeholder;

    final track = widget.width;
    final visibleFraction =
        position.viewportDimension / (position.viewportDimension + maxExtent);
    // A floor, so the thumb stays findable on a very long row.
    final thumb = (track * visibleFraction).clamp(14.0, track);
    final progress = (position.pixels / maxExtent).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Center(
        // Decorative: the scrollable it describes is already announced, and
        // a screen reader has better ways to say "there is more to the right".
        child: ExcludeSemantics(
          child: SizedBox(
            width: track,
            height: 3,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: context.decorativeInk.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Align(
                  // -1 is the left edge and 1 the right, so the thumb travels
                  // the whole track without arithmetic on its own width.
                  alignment: Alignment(progress * 2 - 1, 0),
                  child: Container(
                    width: thumb,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppTheme.brandBlue.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
