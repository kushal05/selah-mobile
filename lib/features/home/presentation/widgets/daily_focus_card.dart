import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/motion_preferences.dart';
import '../../../../l10n/l10n.dart';
import '../../../prayers/presentation/widgets/quick_prayer_sheet.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../bible/presentation/providers/bible_providers.dart';

/// Displays the daily focus prayer card on the home dashboard.
/// Uses a branded blue gradient with glass-style action button.
/// One slide of the hero carousel.
class _Slide {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPressed;
  final List<Color> gradient;

  const _Slide({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
    required this.gradient,
  });
}

/// The hero on the home dashboard.
///
/// It showed one thing — today's prayer — and nothing else on the screen
/// pointed at the rest of the app. It is a carousel now: the prayer, a saved
/// verse, and wherever reading stopped. Slides with no data are left out
/// rather than shown empty, so a new user still sees exactly one card and the
/// carousel appears as the app fills up.
class DailyFocusCard extends ConsumerWidget {
  const DailyFocusCard({super.key});

  /// The day index, from a single clock read.
  ///
  /// The original expression called DateTime.now() twice and could straddle
  /// midnight between them, picking a different item than the day it computed.
  static int _dayOfYear() {
    final now = DateTime.now();
    return now.difference(DateTime(now.year)).inDays;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayers = ref.watch(activePrayersStreamProvider).valueOrNull ?? const [];
    final promises = ref.watch(promisesStreamProvider).valueOrNull ?? const [];
    final history =
        ref.watch(bibleReferenceHistoryStreamProvider).valueOrNull ?? const [];
    final day = _dayOfYear();
    final slides = <_Slide>[];

    // Always present, including its empty state — the carousel never renders
    // with nothing in it.
    if (prayers.isEmpty) {
      slides.add(_Slide(
        eyebrow: l10n(context).dailyFocus,
        title: l10n(context).noActivePrayers,
        subtitle: l10n(context).addAPrayerToGetStarted,
        actionLabel: l10n(context).addPrayer,
        onPressed: () => showQuickPrayerSheet(context),
        gradient: const [AppTheme.brandBlue, AppTheme.gradientEnd],
      ));
    } else {
      final prayer = prayers[day % prayers.length];
      slides.add(_Slide(
        eyebrow: l10n(context).dailyFocus,
        title: prayer.title,
        subtitle: l10n(context).scheduledForToday,
        actionLabel: l10n(context).openPrayer,
        onPressed: () => context.push('/prayers/${prayer.id}'),
        gradient: const [AppTheme.brandBlue, AppTheme.gradientEnd],
      ));
    }

    if (promises.isNotEmpty) {
      final promise = promises[day % promises.length];
      slides.add(_Slide(
        eyebrow: l10n(context).holdOnToThis,
        title: promise.reference.isNotEmpty ? promise.reference : promise.content,
        subtitle: l10n(context).aVerseYouSaved,
        actionLabel: l10n(context).openPromise,
        onPressed: () => context.push('/promises/${promise.id}'),
        gradient: const [AppTheme.brandPurple, AppTheme.rosePink],
      ));
    }

    final last = history.isNotEmpty ? history.first : null;
    if (last != null) {
      slides.add(_Slide(
        eyebrow: l10n(context).keepReading,
        title: '${last.book} ${last.chapter}',
        subtitle: l10n(context).pickUpWhereYouLeftOff,
        actionLabel: l10n(context).resumeReading,
        onPressed: () {
          final book = ref.read(bibleRepositoryProvider).getBookByName(last.book);
          context.push('${Routes.bible}/chapter'
              '?bookId=${book?.id ?? 1}&chapter=${last.chapter}'
              '&translation=${last.translation}');
        },
        gradient: const [AppTheme.emerald, AppTheme.teal],
      ));
    }

    return _FocusCarousel(slides: slides);
  }
}

/// Pages the slides and draws the position dots.
class _FocusCarousel extends StatefulWidget {
  final List<_Slide> slides;
  const _FocusCarousel({required this.slides});

  @override
  State<_FocusCarousel> createState() => _FocusCarouselState();
}

class _FocusCarouselState extends State<_FocusCarousel> {
  final _controller = ScrollController();
  // Slot 0 is the clone of the last slide, so the row has to open one slot in
  // on the real first one. The width is not known until layout, so the jump
  // happens on the first frame rather than at construction.
  bool _positioned = false;
  int _page = 0;
  Timer? _autoScroll;
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  /// Advances a slide every 6 seconds, wrapping at the end.
  ///
  /// Long enough to read a verse reference without feeling hurried. It stops
  /// permanently once the reader swipes: taking the carousel back from
  /// someone who has just chosen a slide is the thing that makes auto-advance
  /// annoying, and it also respects Reduce Motion, where movement nobody
  /// asked for is exactly what the setting is for.
  void _startAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!mounted || !_controller.hasClients || _width <= 0) return;
      // Always forward, never `% length`. Modulo made the last slide rewind
      // through every earlier one to reach the first, which reads as the
      // carousel running backwards rather than looping.
      await _controller.animateTo(
        (_slotIndex + 1) * _width,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
      _normalise();
    });
  }

  /// The slot currently shown, in the padded row's own indexing.
  int get _slotIndex => _page + 1;

  /// Steps off a clone and onto its twin, without moving anything visible.
  ///
  /// The row carries a copy of the last slide before the first and a copy of
  /// the first after the last, so the reader can run off either end. Landing
  /// on a clone is identical on screen to landing on the slide it copies, so
  /// the jump home is invisible and the loop works in both directions.
  void _normalise() {
    if (!mounted || !_controller.hasClients || _width <= 0) return;
    final slot = (_controller.offset / _width).round();
    final n = widget.slides.length;
    if (slot == 0) {
      // Ran off the left onto the clone of the last slide.
      _controller.jumpTo(n * _width);
      setState(() => _page = n - 1);
    } else if (slot == n + 1) {
      // Ran off the right onto the clone of the first.
      _controller.jumpTo(_width);
      setState(() => _page = 0);
    }
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One slide needs no carousel: no scrolling, no dots.
    if (widget.slides.length == 1) {
      return _buildCard(context, widget.slides.first);
    }

    // A scroll view with page physics rather than a PageView.
    //
    // A PageView must be given a height, and every way of computing one is a
    // guess about font metrics — the sibling quick-action row was built that
    // way first and came out 4.8px short, clipping on device while the tests
    // passed. This takes the height of its tallest card instead, so a long
    // verse reference or a raised text size cannot clip it.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Each slide fills the viewport and insets its card by half a gutter
        // on each side, so two cards never touch while swiping. The card is
        // therefore one gutter narrower than the habit cards below it.
        //
        // Widening the viewport instead, to keep the old card width, was tried
        // with an OverflowBox and produced a non-finite semantics rect — the
        // second semantics assertion this widget has thrown. A slightly inset
        // carousel is a normal look; an assert on every frame is not.
        const gap = 12.0;
        final width = constraints.maxWidth;
        _width = width;
        if (!_positioned && width > 0) {
          _positioned = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _controller.hasClients) _controller.jumpTo(width);
          });
        }
        // Reduce Motion: no unrequested movement.
        if (MediaQuery.of(context).disableAnimations) _stopAutoScroll();
        return Column(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // A drag is the reader choosing; stop advancing for them.
                //
                // The direction check is load-bearing: UserScrollNotification
                // also fires with `idle` when a scrollable attaches and when
                // an animation settles, so stopping on any of them killed the
                // timer before the first advance — the carousel never moved
                // on device while the test passed.
                if (n is UserScrollNotification &&
                    n.direction != ScrollDirection.idle) {
                  _stopAutoScroll();
                }
                // Swiped onto the duplicate by hand and let go: settle back
                // onto the real slide one so the reader is never parked on a
                // copy with nowhere left to scroll.
                // Came to rest on a clone after a manual swipe: step onto
                // its twin so there is always more carousel in both
                // directions.
                if (n is ScrollEndNotification) {
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _normalise());
                }
                if (n is ScrollUpdateNotification && width > 0) {
                  // <= length, because the trailing duplicate is a real slot
                  // the reader can also swipe to by hand.
                  // Slot indices include the two clones; _page is the real
                  // slide, so it is the slot minus the leading clone.
                  final slot = (_controller.offset / width).round();
                  final page = slot - 1;
                  if (page != _page &&
                      page >= -1 &&
                      page <= widget.slides.length) {
                    setState(() => _page = page);
                  }
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: const PageScrollPhysics(),
                // IntrinsicHeight, because stretch needs something to stretch
                // to: inside a horizontal scroll view the vertical axis is
                // unconstrained, and a bare stretch asserts at layout. This
                // gives the row the height of its tallest card, so every
                // slide matches without any of them being measured by hand.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Clone of the last slide, so swiping left off the
                      // first has somewhere to go.
                      _slot(context, width, gap, widget.slides.last),
                      for (final slide in widget.slides)
                        _slot(context, width, gap, slide),
                      // Clone of the first, so swiping right off the last
                      // also continues rather than stopping.
                      _slot(context, width, gap, widget.slides.first),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacing12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The trailing duplicate shares slide one's dot: it is
                // slide one, so lighting a different dot would be a lie.
                for (var i = 0; i < widget.slides.length; i++)
                  AnimatedContainer(
                    duration: context.motion(AppTheme.durationFast),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page % widget.slides.length ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page % widget.slides.length
                          ? AppTheme.brandBlue
                          : context.decorativeInk.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// One slot: the card inset by half a gutter, clipped to its own bounds.
  ///
  /// The clip is the fix for a mismatched-looking gutter. Each card casts a
  /// coloured shadow, and without clipping the previous card's shadow painted
  /// across the gap into this slot — sampled at rgb(226,228,247), a blue cast
  /// on a rose slide, against a page ground of rgb(244,245,247). Clipping
  /// keeps each shadow inside its own slot so the gap reads as the page.
  Widget _slot(BuildContext context, double width, double gap, _Slide slide) {
    return SizedBox(
      width: width,
      child: ClipRect(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gap / 2),
          child: _buildCard(context, slide),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, _Slide slide) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: slide.gradient,
        ),
        borderRadius: AppTheme.borderRadius4XL,
        // No shadow. shadowXL is a coloured glow, and with a gutter between
        // slides it painted into that gap — sampled green on the reading
        // slide against a page ground of rgb(244,245,247), which is the
        // "background doesn't match" this looked like. The gradient carries
        // the card on its own; a glow that tints the gap does not earn it.
        boxShadow: null,
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Decorative circles (4, clean positions)
          Positioned(
            top: -30,
            right: -30,
            child: _Circle(size: 120, alpha: AppTheme.alphaLight),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: _Circle(size: 80, alpha: AppTheme.alphaSubtle),
          ),
          Positioned(
            top: 50,
            right: 40,
            child: _Circle(size: 50, alpha: AppTheme.alphaSubtle),
          ),
          Positioned(
            bottom: 50,
            right: -10,
            child: _Circle(size: 70, alpha: 0.05),
          ),

          // Content
          Padding(
            padding: AppTheme.paddingAllLG,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slide.eyebrow,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: AppTheme.tiny.fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing8),
                Text(
                  slide.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  slide.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: AppTheme.alphaText),
                    fontSize: AppTheme.bodySmallStyle.fontSize,
                  ),
                ),
                const SizedBox(height: 18),
                // push keeps Home underneath, so Back returns here; and the
                // empty case opens the quick sheet rather than the long form,
                // matching every other 'add prayer' entry point.
                _GlassActionButton(
                  label: slide.actionLabel,
                  onPressed: slide.onPressed,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle translucent circle used as background decoration.
class _Circle extends StatelessWidget {
  final double size;
  final double alpha;

  const _Circle({required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

/// Glass-style button matching the auth screen GlassButton aesthetic.
class _GlassActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _GlassActionButton({required this.label, required this.onPressed});

  @override
  State<_GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<_GlassActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
      // The action lives on onTap, not onTapUp: only onTap contributes a tap
      // action to the semantics tree, so an onTapUp-only control is inert to
      // TalkBack and VoiceOver. onTapUp still resets the press animation.
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? context.pressScale(0.96) : 1.0,
        duration: context.motion(AppTheme.durationFast),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.spacing20, vertical: AppTheme.spacing10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: AppTheme.alphaMedStrong),
            borderRadius: AppTheme.borderRadiusXL,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.30),
              width: 0.8,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: Colors.white,
              fontSize: AppTheme.bodySmallStyle.fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    ),
    );
  }
}
