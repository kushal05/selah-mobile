import 'package:flutter/material.dart';

import 'base_skeleton.dart';

/// Skeleton that mimics a content card: rectangle block, title, two lines.
class CardSkeleton extends StatelessWidget {
  final double? height;

  const CardSkeleton({super.key, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const BaseSkeleton(height: 14, borderRadius: 4),
          const SizedBox(height: 12),
          BaseSkeleton(
            width: MediaQuery.of(context).size.width * 0.4,
            height: 12,
            borderRadius: 4,
          ),
          const SizedBox(height: 8),
          BaseSkeleton(
            width: MediaQuery.of(context).size.width * 0.25,
            height: 12,
            borderRadius: 4,
          ),
        ],
      ),
    );
  }
}
