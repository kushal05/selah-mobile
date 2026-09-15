import 'package:flutter/material.dart';

import '../../core/services/user_facing_error.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_colors.dart';
import '../../l10n/l10n.dart';

/// What a screen shows when its data could not be loaded.
///
/// Three screens had their own version, two of which offered a retry and one
/// of which did not — so whether a failure was recoverable depended on which
/// screen you happened to be on rather than on the failure.
class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  /// What the user was trying to load, for the message: "notes", "this group".
  final String? what;

  const ErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.what,
  });

  @override
  Widget build(BuildContext context) {
    // Scrollable, because this is shown in whatever space the failing screen
    // had left — sometimes a short panel — and at a large text size the icon,
    // message and button no longer fit. A Column that cannot shrink overflows
    // there instead of degrading, which is how an error state becomes a
    // second error.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: AppTheme.icon4XL, color: context.hintText),
            const SizedBox(height: AppTheme.spacing16),
            Text(
              what == null
                  ? UserFacingError.message(error)
                  : UserFacingError.forLoad(error, what: what!),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: context.mutedText),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppTheme.spacing16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: AppTheme.iconMD),
                label: Text(l10n(context).retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
