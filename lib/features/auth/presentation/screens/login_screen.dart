import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/sync/services/auth_service.dart';
import '../providers/auth_providers.dart';
import '../widgets/aurora_background.dart';
import '../widgets/firefly_particles.dart';
import '../widgets/glass_login_card.dart';
import '../widgets/touch_ripple_layer.dart';
import '../widgets/parallax_container.dart';
import '../widgets/auth_shell.dart';
import '../widgets/daily_scripture_widget.dart';
import '../widgets/google_sign_in_button.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/selah_logo.dart';
import '../widgets/login_entrance_animation.dart';

/// Premium animated login screen with aurora background, glassmorphism card,
/// firefly particles, parallax motion, and sequential entrance animations.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _parallaxKey = GlobalKey<ParallaxContainerState>();
  final _logoKey = GlobalKey<SelahLogoGlowState>();
  final _scriptureKey = GlobalKey<DailyScriptureWidgetState>();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  late final LoginEntranceAnimation _entrance;

  // Button press animation
  late final AnimationController _buttonPressController;
  late final Animation<double> _buttonScaleAnim;

  @override
  void initState() {
    super.initState();
    _entrance = LoginEntranceAnimation(vsync: this);

    _buttonPressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _buttonScaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _buttonPressController, curve: Curves.easeInOut),
    );

    // Start entrance and then enable glow loop
    _entrance.forward();
    _entrance.controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _logoKey.currentState?.startGlow();
        _scriptureKey.currentState?.fadeIn();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _entrance.dispose();
    _buttonPressController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _handleSkip() async {
    final authService = ref.read(authServiceProvider);
    final testToken = AuthToken(
      accessToken: 'test-token',
      refreshToken: 'test-refresh',
      expiresAt: DateTime.now().add(const Duration(days: 365)),
      userId: 'test-user',
    );
    await authService.saveToken(testToken);
    ref.read(currentUserIdProvider.notifier).state = testToken.userId;
    if (mounted) context.go(Routes.home);
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await ref.read(authNotifierProvider.notifier).login(
      LoginRequest(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.go(Routes.home);
    } else {
      final error = ref.read(authNotifierProvider);
      final message = error.error?.toString() ?? 'Login failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);

    final success = await ref.read(authNotifierProvider.notifier).loginWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    if (success) {
      context.go(Routes.home);
    } else {
      final error = ref.read(authNotifierProvider);
      // Don't show error if user just cancelled
      if (error.hasError) {
        final message = error.error?.toString() ?? 'Google login failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  // Uses shared glassInputDecoration from auth_shell.dart

  Widget _buildSignInButton() {
    return FadeTransition(
      opacity: _entrance.buttonFade,
      child: ScaleTransition(
        scale: _entrance.buttonScale,
        child: AnimatedBuilder(
          animation: _buttonScaleAnim,
          builder: (context, child) {
            return Transform.scale(
              scale: _buttonScaleAnim.value,
              child: child,
            );
          },
          child: GestureDetector(
            onTapDown: (_) => _buttonPressController.forward(),
            onTapUp: (_) => _buttonPressController.reverse(),
            onTapCancel: () => _buttonPressController.reverse(),
            child: SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  elevation: 0,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Sign In',
                          key: ValueKey('signin'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navyDark,
      body: ParallaxContainer(
        key: _parallaxKey,
        child: AnimatedBuilder(
          animation: _entrance.controller,
          builder: (context, child) {
            final pOffset =
                _parallaxKey.currentState?.offset ?? Offset.zero;

            return TouchRippleLayer(
              child: Stack(
                children: [
                  // Layer 1: Aurora background with parallax
                  Positioned.fill(
                    child: FadeTransition(
                      opacity: _entrance.backgroundFade,
                      child: ParallaxLayer(
                        magnitude: 2,
                        offset: pOffset,
                        child: const AuroraBackground(),
                      ),
                    ),
                  ),

                  // Layer 2: Firefly particles with parallax
                  Positioned.fill(
                    child: ParallaxLayer(
                      magnitude: 4,
                      offset: pOffset,
                      child: const FireflyParticles(),
                    ),
                  ),

                  // Layer 3: Main content
                  Positioned.fill(
                    child: SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 40,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Logo with parallax and glow
                                ParallaxLayer(
                                  magnitude: 6,
                                  offset: pOffset,
                                  child: ScaleTransition(
                                    scale: _entrance.logoScale,
                                    child: SelahLogoGlow(
                                      key: _logoKey,
                                      size: SelahLogoSize.large,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Greeting + Title
                                FadeTransition(
                                  opacity: _entrance.titleFade,
                                  child: Column(
                                    children: [
                                      Text(
                                        _getGreeting(),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white
                                              .withValues(alpha: 0.6),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Welcome to Selah',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Scripture of the day
                                DailyScriptureWidget(key: _scriptureKey),
                                const SizedBox(height: 32),

                                // Glass login card with parallax
                                ParallaxLayer(
                                  magnitude: 3,
                                  offset: pOffset,
                                  child: SlideTransition(
                                    position: _entrance.formSlide,
                                    child: FadeTransition(
                                      opacity: _entrance.formFade,
                                      child: GlassLoginCard(
                                        child: Form(
                                          key: _formKey,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              // Google sign-in button (primary option)
                                              GoogleSignInButton(
                                                isLoading: _isGoogleLoading,
                                                isDisabled: _isLoading,
                                                onPressed: _handleGoogleLogin,
                                              ),
                                              const SizedBox(height: 16),
                                              const AuthDivider(),
                                              const SizedBox(height: 16),

                                              // Email field
                                              TextFormField(
                                                controller: _emailController,
                                                keyboardType:
                                                    TextInputType.emailAddress,
                                                textInputAction:
                                                    TextInputAction.next,
                                                style: const TextStyle(
                                                    color: Colors.white),
                                                cursorColor: Colors.white,
                                                decoration:
                                                    glassInputDecoration(
                                                  context: context,
                                                  label: 'Email',
                                                  hint: 'Enter your email',
                                                  prefixIcon:
                                                      Icons.email_outlined,
                                                ),
                                                validator: (value) {
                                                  if (value == null ||
                                                      value.trim().isEmpty) {
                                                    return 'Please enter your email';
                                                  }
                                                  if (!value.contains('@') ||
                                                      !value.contains('.')) {
                                                    return 'Please enter a valid email';
                                                  }
                                                  return null;
                                                },
                                              ),
                                              const SizedBox(height: 16),

                                              // Password field
                                              TextFormField(
                                                controller:
                                                    _passwordController,
                                                obscureText: _obscurePassword,
                                                textInputAction:
                                                    TextInputAction.done,
                                                onFieldSubmitted: (_) =>
                                                    _handleLogin(),
                                                style: const TextStyle(
                                                    color: Colors.white),
                                                cursorColor: Colors.white,
                                                decoration:
                                                    glassInputDecoration(
                                                  context: context,
                                                  label: 'Password',
                                                  hint: 'Enter your password',
                                                  prefixIcon:
                                                      Icons.lock_outlined,
                                                  suffixIcon: IconButton(
                                                    icon: Icon(
                                                      _obscurePassword
                                                          ? Icons
                                                              .visibility_off_outlined
                                                          : Icons
                                                              .visibility_outlined,
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.7),
                                                    ),
                                                    onPressed: () {
                                                      setState(() =>
                                                          _obscurePassword =
                                                              !_obscurePassword);
                                                    },
                                                  ),
                                                ),
                                                validator: (value) {
                                                  if (value == null ||
                                                      value.isEmpty) {
                                                    return 'Please enter your password';
                                                  }
                                                  if (value.length < 8) {
                                                    return 'Password must be at least 8 characters';
                                                  }
                                                  return null;
                                                },
                                              ),
                                              const SizedBox(height: 8),

                                              // Forgot password
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: TextButton(
                                                  onPressed: () => context.push(
                                                      Routes.forgotPassword),
                                                  child: Text(
                                                    'Forgot password?',
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                              alpha: 0.7),
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),

                                              // Sign in button with press animation
                                              _buildSignInButton(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Register link
                                FadeTransition(
                                  opacity: _entrance.buttonFade,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Don't have an account? ",
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            context.go(Routes.register),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize
                                                  .shrinkWrap,
                                        ),
                                        child: const Text(
                                          'Register',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Skip for testing (debug only)
                                if (kDebugMode) ...[
                                  const SizedBox(height: 12),
                                  FadeTransition(
                                    opacity: _entrance.buttonFade,
                                    child: TextButton(
                                      onPressed: _handleSkip,
                                      child: Text(
                                        'Skip (Testing)',
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
