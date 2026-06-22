import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Displays a prayer focus card in the prayers dashboard
class PrayerFocusCard extends StatelessWidget {
  final String title;
  final String frequency;
  final VoidCallback? onTap;
  final VoidCallback? onLogPress;

  const PrayerFocusCard({
    super.key,
    required this.title,
    required this.frequency,
    this.onTap,
    this.onLogPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacing12),
        padding: AppTheme.paddingAllBase,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppTheme.borderRadiusXL,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.brandBlue.withValues(alpha: AppTheme.alphaLightMed),
                borderRadius: AppTheme.borderRadiusXL,
              ),
              child: const Icon(
                Icons.favorite,
                color: AppTheme.brandBlue,
              ),
            ),
            const SizedBox(width: AppTheme.spacing16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  Text(
                    frequency,
                    style: AppTheme.bodyBase.copyWith(
                      color: AppTheme.gray600,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onLogPress,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brandBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16, vertical: AppTheme.spacing8),
              ),
              child: const Text('Log'),
            ),
          ],
        ),
      ),
    );
  }
}
