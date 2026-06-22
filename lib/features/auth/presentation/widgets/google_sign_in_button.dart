import 'package:flutter/material.dart';

/// Glass-styled Google Sign-In button matching the auth screen theme.
class GoogleSignInButton extends StatelessWidget {
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback? onPressed;

  const GoogleSignInButton({
    super.key,
    this.isLoading = false,
    this.isDisabled = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: (isLoading || isDisabled) ? null : onPressed,
        icon: isLoading
            ? const SizedBox.shrink()
            : Image.asset(
                'assets/google_logo.png',
                height: 20,
                width: 20,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.g_mobiledata, size: 24),
              ),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isLoading
              ? const SizedBox(
                  key: ValueKey('google_loading'),
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Continue with Google',
                  key: ValueKey('google_label'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

/// "or" divider used between Google sign-in and email/password form.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}
