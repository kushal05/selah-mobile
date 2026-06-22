import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/remote/icon_registry.dart';
import '../../../../core/config/remote/remote_config_keys.dart';
import '../../../../core/config/remote/remote_config_providers.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/firefly_particles.dart';

/// Premium animated onboarding screen shown on first launch.
///
/// 4-page Headspace-style flow with multi-layered illustrations, parallax
/// between pages, sliding indicator pill, and gradient CTA button.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;
  double _pageOffset = 0;

  // Screen entrance
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;

  // Per-page content stagger
  late final AnimationController _pageEntranceController;
  late final Animation<double> _iconScale;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleFade;

  // Bottom section entrance
  late final AnimationController _bottomController;
  late final Animation<double> _bottomFade;
  late final Animation<Offset> _bottomSlide;

  /// Effective onboarding pages: backend override if present, else the bundled
  /// defaults. Read (not watched) — onboarding is a one-shot flow and we don't
  /// need it to rebuild mid-swipe if config refreshes.
  List<_OnboardingPageData> get _pages {
    final raw = ref.read(remoteConfigProvider).getJsonList(RcKeys.onboardingPages);
    if (raw.isEmpty) return _defaultPages;
    final pages = <_OnboardingPageData>[];
    for (final item in raw) {
      if (item is Map) pages.add(_OnboardingPageData.fromConfig(item));
    }
    // Never render a blank flow — fall back if the override yielded nothing.
    return pages.isEmpty ? _defaultPages : pages;
  }

  static const _defaultPages = [
    _OnboardingPageData(
      icon: Icons.auto_awesome_rounded, // unused — useAppIcon renders the PNG instead
      title: 'Welcome to Selah',
      subtitle: 'Pause. Reflect. Grow.',
      color: AppTheme.brandPurple,
      orbitIcons: [Icons.spa_outlined, Icons.light_mode_outlined],
      useAppIcon: true,
    ),
    _OnboardingPageData(
      icon: Icons.menu_book_rounded,
      title: 'Capture what God\nteaches you',
      subtitle:
          'Take sermon notes, highlight scripture, and organize your spiritual insights in one beautiful place.',
      color: AppTheme.brandBlue,
      orbitIcons: [Icons.edit_note_rounded, Icons.bookmark_add_outlined],
    ),
    _OnboardingPageData(
      icon: Icons.favorite_rounded,
      title: 'Keep track of\nyour prayers',
      subtitle:
          'Record prayer requests, track answers, and build a journal of God\'s faithfulness over time.',
      color: AppTheme.onboardingBlue,
      orbitIcons: [Icons.bookmark_rounded, Icons.star_outline_rounded],
    ),
    _OnboardingPageData(
      icon: Icons.people_rounded,
      title: 'Grow together',
      subtitle:
          'Share prayer requests with friends, join groups, and encourage one another in your faith journey.',
      color: AppTheme.onboardingPurple,
      orbitIcons: [Icons.church_rounded, Icons.handshake_outlined],
    ),
  ];

  @override
  void initState() {
    super.initState();

    // Track page scroll position for parallax
    _pageController.addListener(() {
      if (_pageController.page != null) {
        setState(() => _pageOffset = _pageController.page!);
      }
    });

    // Screen entrance (800ms)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));

    // Per-page content stagger (700ms)
    _pageEntranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _iconScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pageEntranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pageEntranceController,
        curve: const Interval(0.15, 0.6, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _pageEntranceController,
      curve: const Interval(0.15, 0.6, curve: Curves.easeOutCubic),
    ));
    _subtitleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pageEntranceController,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
      ),
    );

    // Bottom section entrance (600ms, delayed start)
    _bottomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bottomFade = CurvedAnimation(
      parent: _bottomController,
      curve: Curves.easeOut,
    );
    _bottomSlide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _bottomController,
      curve: Curves.easeOutCubic,
    ));

    _entranceController.forward();
    _pageEntranceController.forward();
    // Delay bottom entrance slightly
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _bottomController.forward();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entranceController.dispose();
    _pageEntranceController.dispose();
    _bottomController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (mounted) {
      context.go(Routes.register);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _pageEntranceController.reset();
    _pageEntranceController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navyDark,
      body: Stack(
        children: [
          // Aurora background
          const Positioned.fill(child: AuroraBackground()),

          // Particles
          const Positioned.fill(child: FireflyParticles()),

          // Content
          SafeArea(
            child: FadeTransition(
              opacity: _entranceFade,
              child: SlideTransition(
                position: _entranceSlide,
                child: Column(
                  children: [
                    // Skip button — glass pill style
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppTheme.spacing16, top: AppTheme.spacing12),
                        child: TextButton(
                          onPressed: _completeOnboarding,
                          style: TextButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: AppTheme.alphaLight),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppTheme.borderRadius4XL,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing16,
                              vertical: AppTheme.spacing8,
                            ),
                          ),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: AppTheme.bodyBase.fontSize,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Pages
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _pages.length,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, index) {
                          final page = _pages[index];
                          // Parallax offset for this page
                          final parallax =
                              ((index - _pageOffset) * 40).clamp(-80.0, 80.0);

                          return AnimatedBuilder(
                            animation: _pageEntranceController,
                            builder: (context, child) {
                              return _OnboardingPageWidget(
                                page: page,
                                parallaxOffset: parallax,
                                iconScale: index == _currentPage
                                    ? _iconScale.value
                                    : 1.0,
                                titleOpacity: index == _currentPage
                                    ? _titleFade.value
                                    : 1.0,
                                titleOffset: index == _currentPage
                                    ? _titleSlide.value
                                    : Offset.zero,
                                subtitleOpacity: index == _currentPage
                                    ? _subtitleFade.value
                                    : 1.0,
                              );
                            },
                          );
                        },
                      ),
                    ),

                    // Bottom section with entrance animation
                    FadeTransition(
                      opacity: _bottomFade,
                      child: SlideTransition(
                        position: _bottomSlide,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(AppTheme.spacing24, 0, AppTheme.spacing24, AppTheme.spacing32),
                          child: Column(
                            children: [
                              // Sliding indicator
                              _PageIndicator(
                                pageCount: _pages.length,
                                currentPage: _currentPage,
                                pageOffset: _pageOffset,
                              ),
                              const SizedBox(height: AppTheme.spacing32),

                              // CTA button — gradient on last page, glass otherwise
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: _buildActionButton(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    final isLastPage = _currentPage == _pages.length - 1;

    return AnimatedContainer(
      duration: AppTheme.durationSlow,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: AppTheme.borderRadius3XL,
        gradient: isLastPage
            ? const LinearGradient(
                colors: [AppTheme.brandPurple, AppTheme.brandBlue],
              )
            : null,
        color: isLastPage ? null : Colors.white.withValues(alpha: AppTheme.alphaMedLight),
        border: Border.all(
          color: isLastPage
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.25),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppTheme.borderRadius3XL,
          onTap: () {
            if (isLastPage) {
              _completeOnboarding();
            } else {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOutCubic,
              );
            }
          },
          child: Center(
            child: AnimatedSwitcher(
              duration: AppTheme.durationMedium,
              child: Text(
                isLastPage ? 'Get Started' : 'Continue',
                key: ValueKey(isLastPage),
                style: TextStyle(
                  fontSize: AppTheme.headingSmall.fontSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Page indicator with a sliding highlight pill.
class _PageIndicator extends StatelessWidget {
  final int pageCount;
  final int currentPage;
  final double pageOffset;

  const _PageIndicator({
    required this.pageCount,
    required this.currentPage,
    required this.pageOffset,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(pageCount, (index) {
          // Smooth interpolation based on actual scroll position
          final distance = (index - pageOffset).abs().clamp(0.0, 1.0);
          final width = 8.0 + (1.0 - distance) * 20.0;
          final opacity = 0.3 + (1.0 - distance) * 0.7;

          return AnimatedContainer(
            duration: AppTheme.durationMedium,
            curve: Curves.easeInOut,
            margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacing3),
            width: width,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: AppTheme.borderRadiusXS,
              color: Colors.white.withValues(alpha: opacity),
            ),
          );
        }),
      ),
    );
  }
}

/// A single onboarding page with multi-layered illustration.
class _OnboardingPageWidget extends StatelessWidget {
  final _OnboardingPageData page;
  final double parallaxOffset;
  final double iconScale;
  final double titleOpacity;
  final Offset titleOffset;
  final double subtitleOpacity;

  const _OnboardingPageWidget({
    required this.page,
    required this.parallaxOffset,
    required this.iconScale,
    required this.titleOpacity,
    required this.titleOffset,
    required this.subtitleOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration with parallax
          Transform.translate(
            offset: Offset(parallaxOffset, 0),
            child: Transform.scale(
              scale: iconScale,
              child: _PremiumIllustration(
                color: page.color,
                icon: page.icon,
                orbitIcons: page.orbitIcons,
                useAppIcon: page.useAppIcon,
              ),
            ),
          ),
          const SizedBox(height: 48),

          // Title
          Opacity(
            opacity: titleOpacity,
            child: FractionalTranslation(
              translation: titleOffset,
              child: Text(
                page.title,
                style: TextStyle(
                  fontSize: AppTheme.headingLarge.fontSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing16),

          // Subtitle
          Opacity(
            opacity: subtitleOpacity,
            child: Text(
              page.subtitle,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha: AppTheme.alphaText),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Multi-layered illustration: gradient ring → glass circle → main icon,
/// with orbiting glass pills containing secondary icons.
class _PremiumIllustration extends StatefulWidget {
  final Color color;
  final IconData icon;
  final List<IconData> orbitIcons;
  final bool useAppIcon;

  const _PremiumIllustration({
    required this.color,
    required this.icon,
    required this.orbitIcons,
    this.useAppIcon = false,
  });

  @override
  State<_PremiumIllustration> createState() => _PremiumIllustrationState();
}

class _PremiumIllustrationState extends State<_PremiumIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitController;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return SizedBox(
      width: 240,
      height: 240,
      child: AnimatedBuilder(
        animation: reduceMotion
            ? const AlwaysStoppedAnimation(0)
            : _orbitController,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      widget.color.withValues(alpha: 0.2),
                      widget.color.withValues(alpha: 0.08),
                      widget.color.withValues(alpha: 0),
                    ],
                    stops: const [0.3, 0.6, 1.0],
                  ),
                ),
              ),

              // Middle ring border
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
              ),

              // Inner frosted glass circle with icon
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.12),
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: widget.useAppIcon
                    ? ClipOval(
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 140,
                          height: 140,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(
                        widget.icon,
                        size: 64,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
              ),

              // Orbiting glass pills
              for (int i = 0; i < widget.orbitIcons.length; i++)
                _buildOrbitPill(i),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOrbitPill(int index) {
    final angle = _orbitController.value * 2 * pi +
        (index * 2 * pi / widget.orbitIcons.length);
    final radius = 100.0;
    final x = cos(angle) * radius;
    final y = sin(angle) * radius * 0.4; // Elliptical orbit

    // Fade based on position (dimmer when "behind")
    final depthFade = (sin(angle) + 1) / 2; // 0 at back, 1 at front
    final opacity = 0.4 + depthFade * 0.6;
    final scale = 0.8 + depthFade * 0.2;

    return Transform.translate(
      offset: Offset(x, y),
      child: Transform.scale(
        scale: scale,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.2),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              widget.orbitIcons[index],
              size: AppTheme.iconBase,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<IconData> orbitIcons;
  final bool useAppIcon;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.orbitIcons,
    this.useAppIcon = false,
  });

  /// Builds a page from a remote-config map, resolving icon names through the
  /// registry and the hex colour through [colorFromHex], with safe fallbacks.
  factory _OnboardingPageData.fromConfig(Map<dynamic, dynamic> m) {
    final orbits = (m['orbitIcons'] as List?)
            ?.map((n) => iconFor(n?.toString()))
            .toList() ??
        const <IconData>[];
    return _OnboardingPageData(
      icon: iconFor(m['icon']?.toString(), fallback: Icons.auto_awesome_rounded),
      title: m['title']?.toString() ?? '',
      subtitle: m['subtitle']?.toString() ?? '',
      color: colorFromHex(m['color']?.toString()) ?? AppTheme.brandPurple,
      orbitIcons: orbits,
      useAppIcon: m['useAppIcon'] == true,
    );
  }
}
