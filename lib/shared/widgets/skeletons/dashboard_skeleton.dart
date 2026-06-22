import 'package:flutter/material.dart';

import 'base_skeleton.dart';
import 'grid_card_skeleton.dart';

/// Skeleton that mimics a dashboard: greeting, card grid, action rows.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          BaseSkeleton(width: width * 0.5, height: 22, borderRadius: 6),
          const SizedBox(height: 8),
          BaseSkeleton(width: width * 0.3, height: 14, borderRadius: 4),
          const SizedBox(height: 24),

          // Banner placeholder
          const BaseSkeleton(height: 72, borderRadius: 12),
          const SizedBox(height: 16),

          // Section title
          BaseSkeleton(width: width * 0.3, height: 16, borderRadius: 4),
          const SizedBox(height: 12),

          // Card grid 2x2
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: const [
              GridCardSkeleton(),
              GridCardSkeleton(),
              GridCardSkeleton(),
              GridCardSkeleton(),
            ],
          ),
          const SizedBox(height: 24),

          // Section title
          BaseSkeleton(width: width * 0.35, height: 16, borderRadius: 4),
          const SizedBox(height: 12),

          // Action row placeholders
          const BaseSkeleton(height: 56, borderRadius: 12),
          const SizedBox(height: 12),
          const BaseSkeleton(height: 56, borderRadius: 12),
        ],
      ),
    );
  }
}
