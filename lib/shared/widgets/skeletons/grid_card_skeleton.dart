import 'package:flutter/material.dart';

import 'base_skeleton.dart';

/// Skeleton that mimics a grid card: colored rectangle block with a title.
class GridCardSkeleton extends StatelessWidget {
  const GridCardSkeleton({super.key});

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
          const BaseSkeleton(width: 60, height: 12, borderRadius: 4),
          const BaseSkeleton(width: 40, height: 22, borderRadius: 4),
        ],
      ),
    );
  }
}
