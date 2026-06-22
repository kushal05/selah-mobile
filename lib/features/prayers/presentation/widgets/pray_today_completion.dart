import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Completion screen shown when all daily prayers are logged
class PrayTodayCompletion extends StatelessWidget {
  final int totalPrayers;
  final VoidCallback onReviewLogs;
  final VoidCallback onAddReflection;
  final VoidCallback onExit;

  const PrayTodayCompletion({
    super.key,
    required this.totalPrayers,
    required this.onReviewLogs,
    required this.onAddReflection,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Celebration icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.teal.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 48,
                color: AppTheme.teal,
              ),
            ),
            const SizedBox(height: 24),

            // Completion message
            Text(
              "You've completed today's prayers",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$totalPrayers prayer${totalPrayers == 1 ? '' : 's'} logged',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAddReflection,
                icon: const Icon(Icons.edit_note, size: 20),
                label: const Text('Add a Reflection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brandBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReviewLogs,
                icon: const Icon(Icons.history, size: 20),
                label: const Text('Review Logs'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.brandBlue,
                  side: const BorderSide(color: AppTheme.brandBlue),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onExit,
              child: Text(
                'Done',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
