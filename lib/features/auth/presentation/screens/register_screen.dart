import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/tutorial/tutorial_providers.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_shell.dart';
import '../widgets/glass_login_card.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/selah_logo.dart';

/// Premium registration screen — dark aurora theme with glass inputs,
/// staggered entrance animation, and branded logo.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _emailAvailabilityError;
  bool _isCheckingEmail = false;
  bool _emailAvailable = false;

  // Entrance animation — single controller, two derived animations
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _emailFocusNode.addListener(_onEmailFocusChanged);

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));

    _entranceController.forward();
  }

  @override
  void dispose() {
    _emailFocusNode.removeListener(_onEmailFocusChanged);
    _emailFocusNode.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _onEmailFocusChanged() {
    if (!_emailFocusNode.hasFocus) {
      _checkEmailAvailability();
    }
  }

  Future<void> _checkEmailAvailability() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _emailAvailable = false;
    });
    final error = await ref
        .read(authNotifierProvider.notifier)
        .checkEmailAvailability(email);
    if (!mounted) return;
    setState(() {
      _emailAvailabilityError = error;
      _isCheckingEmail = false;
      _emailAvailable = error == null;
    });
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);

    final success = await ref.read(authNotifierProvider.notifier).loginWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    if (success) {
      ref.read(tutorialServiceProvider).setPending();
      if (mounted) context.go(Routes.home);
    } else {
      final error = ref.read(authNotifierProvider);
      if (error.hasError) {
        final message = error.error?.toString() ?? 'Google sign-up failed';
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

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Check email availability before submitting
    final emailError = await ref
        .read(authNotifierProvider.notifier)
        .checkEmailAvailability(_emailController.text.trim());
    if (!mounted) return;
    if (emailError != null) {
      setState(() {
        _emailAvailabilityError = emailError;
        _isLoading = false;
      });
      _formKey.currentState!.validate();
      return;
    }

    final success = await ref.read(authNotifierProvider.notifier).register(
      RegisterRequest(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      ),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      if (mounted) context.go(Routes.home);
    } else {
      final error = ref.read(authNotifierProvider);
      final message = error.error?.toString() ?? 'Registration failed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Widget _buildEmailSuffix() {
    if (_isCheckingEmail) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return const SizedBox.shrink();
    }

    if (_emailAvailable) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Icon(
            Icons.check_circle_rounded,
            color: Colors.green.shade300,
            size: 22,
          ),
        ),
      );
    }

    if (_emailAvailabilityError != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          Icons.cancel_rounded,
          color: Colors.amber.shade300,
          size: 22,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      showBackButton: true,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo
              const SelahLogo(size: SelahLogoSize.medium),
              const SizedBox(height: 24),

              // Title + subtitle
              Column(
                children: [
                  const Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign up to get started',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Glass form card
              GlassLoginCard(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Google sign-up button (primary option)
                      GoogleSignInButton(
                        isLoading: _isGoogleLoading,
                        isDisabled: _isLoading,
                        onPressed: _handleGoogleLogin,
                      ),
                      const SizedBox(height: 16),
                      const AuthDivider(),
                      const SizedBox(height: 16),

                      // Name
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: glassInputDecoration(
                          context: context,
                          label: 'Full Name',
                          hint: 'Enter your name',
                          prefixIcon: Icons.person_outlined,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Email
                      TextFormField(
                        controller: _emailController,
                        focusNode: _emailFocusNode,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: glassInputDecoration(
                          context: context,
                          label: 'Email',
                          hint: 'Enter your email',
                          prefixIcon: Icons.email_outlined,
                          suffixIcon: _buildEmailSuffix(),
                        ),
                        onChanged: (_) {
                          if (_emailAvailabilityError != null ||
                              _emailAvailable) {
                            setState(() {
                              _emailAvailabilityError = null;
                              _emailAvailable = false;
                            });
                          }
                        },
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@') ||
                              !value.contains('.')) {
                            return 'Please enter a valid email';
                          }
                          if (_emailAvailabilityError != null) {
                            return _emailAvailabilityError;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: glassInputDecoration(
                          context: context,
                          label: 'Password',
                          hint: 'Create a password',
                          prefixIcon: Icons.lock_outlined,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color:
                                  Colors.white.withValues(alpha: 0.7),
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (value.length < 8) {
                            return 'Password must be at least 8 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Confirm password
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleRegister(),
                        style: const TextStyle(color: Colors.white),
                        cursorColor: Colors.white,
                        decoration: glassInputDecoration(
                          context: context,
                          label: 'Confirm Password',
                          hint: 'Re-enter your password',
                          prefixIcon: Icons.lock_outlined,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color:
                                  Colors.white.withValues(alpha: 0.7),
                            ),
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Register button
                      GlassButton(
                        label: 'Create Account',
                        isLoading: _isLoading,
                        onPressed: _isGoogleLoading ? null : _handleRegister,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Login link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go(Routes.login),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Sign In',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
