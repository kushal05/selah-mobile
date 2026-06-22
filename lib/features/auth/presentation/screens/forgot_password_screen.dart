import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_shell.dart';
import '../widgets/glass_login_card.dart';
import '../widgets/selah_logo.dart';

/// Premium forgot-password screen — dark aurora theme with glass inputs,
/// entrance animation, and animated crossfade to success state.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleFade;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;

  // Success state transition
  late final AnimationController _successController;
  late final Animation<double> _successFade;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    ));
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack),
    ));
    _titleFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.1, 0.4, curve: Curves.easeOut),
    ));
    _formFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 0.55, curve: Curves.easeOut),
    ));
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 0.55, curve: Curves.easeOutCubic),
    ));

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successFade = CurvedAnimation(
      parent: _successController,
      curve: Curves.easeOut,
    );
    _successScale = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.easeOutBack),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _entranceController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _handleSendReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    await ref.read(authNotifierProvider.notifier).forgotPassword(
      _emailController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _emailSent = true;
    });
    _successController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      showBackButton: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([_entranceController, _successController]),
        builder: (context, child) {
          return AnimatedCrossFade(
            duration: const Duration(milliseconds: 400),
            crossFadeState: _emailSent
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: _buildFormState(),
            secondChild: _buildSuccessState(),
            sizeCurve: Curves.easeInOut,
          );
        },
      ),
    );
  }

  Widget _buildFormState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo
        FadeTransition(
          opacity: _logoFade,
          child: ScaleTransition(
            scale: _logoScale,
            child: const SelahLogo(size: SelahLogoSize.medium),
          ),
        ),
        const SizedBox(height: 24),

        // Title + description
        FadeTransition(
          opacity: _titleFade,
          child: Column(
            children: [
              const Text(
                'Reset Password',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your email and we\'ll send you\na link to reset your password.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Glass form card
        FadeTransition(
          opacity: _formFade,
          child: SlideTransition(
            position: _formSlide,
            child: GlassLoginCard(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleSendReset(),
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: glassInputDecoration(
                        context: context,
                        label: 'Email',
                        hint: 'Enter your email',
                        prefixIcon: Icons.email_outlined,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    GlassButton(
                      label: 'Send Reset Link',
                      isLoading: _isLoading,
                      onPressed: _handleSendReset,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return FadeTransition(
      opacity: _successFade,
      child: ScaleTransition(
        scale: _successScale,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Success icon with glow
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.15),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.mark_email_read_rounded,
                size: 40,
                color: Colors.green.shade300,
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Check Your Email',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            Text(
              'If an account exists with\n${_emailController.text.trim()},\nwe\'ve sent a password reset link.',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            TextButton(
              onPressed: () => context.pop(),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Back to Sign In',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
