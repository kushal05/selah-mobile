import 'package:flutter/material.dart';

import 'base_skeleton.dart';

/// Skeleton that mimics a form: input field placeholders and a button.
class FormSkeleton extends StatelessWidget {
  final int fieldCount;

  const FormSkeleton({super.key, this.fieldCount = 4});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < fieldCount; i++) ...[
            // Field label
            BaseSkeleton(
              width: 80 + (i * 12).toDouble(),
              height: 12,
              borderRadius: 4,
            ),
            const SizedBox(height: 8),
            // Field input
            const BaseSkeleton(height: 48, borderRadius: 8),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 8),
          // Submit button
          const BaseSkeleton(height: 48, borderRadius: 24),
        ],
      ),
    );
  }
}
