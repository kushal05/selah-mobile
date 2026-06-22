import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../widgets/aurora_background.dart';
import '../widgets/firefly_particles.dart';
import '../widgets/selah_logo.dart';

/// Premium splash screen shown on app launch.
///
/// Aurora background + branded logo with staggered entrance animation,
/// then a graceful fade-out before navigating to the next screen.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // Entrance: logo scale → wordmark fade → tagline slide
  late final AnimationController _entranceController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _wordmarkFade;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _taglineSlide;

  // Exit: everything fades + scales down
  late final AnimationController _exitController;
  late final Animation<double> _exitFade;
  late final Animation<double> _exitScale;

  @override
  void initState() {
    super.initState();

    // Entrance animation (1200ms total)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _wordmarkFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
      ),
    );
    _taglineFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOut),
      ),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.4, 0.8, curve: Curves.easeOutCubic),
    ));

    // Exit animation (200ms — kept short so it doesn't gate navigation)
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _exitFade = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );
    _exitScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );

    _entranceController.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    final authService = ref.read(authServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final hasUser = authService.currentToken != null;

    // Run minimum display time in parallel with the profile check so
    // cold starts don't feel slower. 800ms is enough for the entrance
    // animation to land the wordmark + tagline; the previous 1800ms was
    // a perceptible drag on cold start.
    final minDelay = Future.delayed(const Duration(milliseconds: 800));

    // Start profile fetch early (only if logged in) so it runs during
    // the splash animation instead of after it.
    final profileCheck = hasUser ? _checkProfile() : Future.value();

    await Future.wait([minDelay, profileCheck]);
    if (!mounted) return;

    // Play exit animation before navigating
    await _exitController.forward();
    if (!mounted) return;

    if (!hasUser) {
      final hasSeenOnboarding =
          prefs.getBool('has_seen_onboarding') ?? false;
      if (hasSeenOnboarding) {
        context.go(Routes.login);
      } else {
        context.go(Routes.onboarding);
      }
      return;
    }

    context.go(Routes.home);
  }

  /// Fetch the user's profile and set [profileCompleteProvider] so the
  /// router redirect has the correct value on cold start (during login
  /// this is handled by [AuthNotifier]).
  Future<void> _checkProfile() async {
    try {
      final api = ref.read(friendsApiServiceProvider);
      final profile = await api.getCurrentProfile();
      final isComplete = profile != null &&
          profile.username.trim().isNotEmpty &&
          profile.displayName.trim().isNotEmpty;
      ref.read(profileCompleteProvider.notifier).state = isComplete;
    } catch (_) {
      // Network/server error — assume complete so the user isn't blocked
      // from the app. The watcher will correct it if needed later.
      ref.read(profileCompleteProvider.notifier).state = true;
    }
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navyDark,
      body: AnimatedBuilder(
        animation: Listenable.merge([_entranceController, _exitController]),
        builder: (context, child) {
          return FadeTransition(
            opacity: _exitFade,
            child: ScaleTransition(
              scale: _exitScale,
              child: Stack(
                children: [
                  // Aurora background
                  const Positioned.fill(child: AuroraBackground()),

                  // Particles
                  const Positioned.fill(child: FireflyParticles()),

                  // Center content
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo icon with scale + fade
                        FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: const SelahLogo(
                              size: SelahLogoSize.large,
                              showWordmark: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Wordmark
                        FadeTransition(
                          opacity: _wordmarkFade,
                          child: const Text(
                            'Selah',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Tagline
                        FadeTransition(
                          opacity: _taglineFade,
                          child: SlideTransition(
                            position: _taglineSlide,
                            child: Text(
                              'Pause. Reflect. Grow.',
                              style: TextStyle(
                                fontSize: 16,
                                color:
                                    Colors.white.withValues(alpha: 0.7),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
