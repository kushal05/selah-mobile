import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/tutorial/tutorial_providers.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_shell.dart';
import '../widgets/glass_login_card.dart';
import '../widgets/selah_logo.dart';

/// Premium profile-completion screen — dark aurora theme with glass inputs,
/// entrance animation, and animated username availability feedback.
class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState
    extends ConsumerState<CompleteProfileScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  bool _isSaving = false;
  String? _usernameAvailabilityError;
  bool _isCheckingUsername = false;
  bool _usernameAvailable = false;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleFade;
  late final Animation<double> _formFade;
  late final Animation<Offset> _formSlide;

  @override
  void initState() {
    super.initState();
    _usernameFocusNode.addListener(_onUsernameFocusChanged);

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

    _entranceController.forward();
  }

  @override
  void dispose() {
    _usernameFocusNode.removeListener(_onUsernameFocusChanged);
    _usernameFocusNode.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _onUsernameFocusChanged() {
    if (!_usernameFocusNode.hasFocus) {
      _checkUsernameAvailability();
    }
  }

  Future<void> _checkUsernameAvailability() async {
    final username = _usernameController.text.trim().toLowerCase();
    if (username.length < 3 ||
        !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameAvailable = false;
    });
    final error = await ref
        .read(authNotifierProvider.notifier)
        .checkUsernameAvailability(username);
    if (!mounted) return;
    setState(() {
      _usernameAvailabilityError = error;
      _isCheckingUsername = false;
      _usernameAvailable = error == null;
    });
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // Check username availability before saving
    final usernameError = await ref
        .read(authNotifierProvider.notifier)
        .checkUsernameAvailability(
            _usernameController.text.trim().toLowerCase());
    if (!mounted) return;
    if (usernameError != null) {
      setState(() {
        _usernameAvailabilityError = usernameError;
        _isSaving = false;
      });
      _formKey.currentState!.validate();
      return;
    }

    try {
      final api = ref.read(friendsApiServiceProvider);
      await api.updateProfile(
        username: _usernameController.text.trim().toLowerCase(),
        displayName: _displayNameController.text.trim(),
      );

      ref.read(profileCompleteProvider.notifier).state = true;

      ref.read(tutorialServiceProvider).setPending();

      // Request notification permission now that the user has context.
      // Best-effort: never block navigation on permission outcome.
      await FcmService.instance.requestPermission().catchError((_) => false);

      if (mounted) {
        context.go(Routes.home);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  Widget _buildUsernameSuffix() {
    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    final username = _usernameController.text.trim();
    if (username.length < 3) return const SizedBox.shrink();

    if (_usernameAvailable) {
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

    if (_usernameAvailabilityError != null) {
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
    return PopScope(
      canPop: false,
      child: AuthShell(
        child: AnimatedBuilder(
          animation: _entranceController,
          builder: (context, child) {
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

                // Title + subtitle
                FadeTransition(
                  opacity: _titleFade,
                  child: Column(
                    children: [
                      const Text(
                        'Complete Your Profile',
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
                        'Choose a username and display name\nto get started',
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
                            // Username
                            TextFormField(
                              controller: _usernameController,
                              focusNode: _usernameFocusNode,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              decoration: glassInputDecoration(
                                context: context,
                                label: 'Username',
                                hint: 'Choose a username',
                                prefixIcon: Icons.alternate_email,
                                suffixIcon: _buildUsernameSuffix(),
                              ),
                              onChanged: (_) {
                                if (_usernameAvailabilityError != null) {
                                  setState(() {
                                    _usernameAvailabilityError = null;
                                    _usernameAvailable = false;
                                  });
                                }
                              },
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Username is required';
                                }
                                if (value.trim().length < 3) {
                                  return 'Username must be at least 3 characters';
                                }
                                if (!RegExp(r'^[a-zA-Z0-9_]+$')
                                    .hasMatch(value.trim())) {
                                  return 'Only letters, numbers, and underscores';
                                }
                                if (_usernameAvailabilityError != null) {
                                  return _usernameAvailabilityError;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text(
                                'Your unique username for friends to find you',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Display name
                            TextFormField(
                              controller: _displayNameController,
                              textInputAction: TextInputAction.done,
                              textCapitalization: TextCapitalization.words,
                              onFieldSubmitted: (_) => _handleContinue(),
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.white,
                              decoration: glassInputDecoration(
                                context: context,
                                label: 'Display Name',
                                hint: 'Enter your display name',
                                prefixIcon: Icons.badge_outlined,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Display name is required';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),

                            // Continue button
                            GlassButton(
                              label: 'Continue',
                              isLoading: _isSaving,
                              onPressed: _handleContinue,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
