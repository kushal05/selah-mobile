import 'package:flutter/material.dart';

import 'base_skeleton.dart';

/// Skeleton that mimics a feed item: avatar, title, body text lines.
class FeedItemSkeleton extends StatelessWidget {
  const FeedItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BaseSkeleton.circle(size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BaseSkeleton(
                  width: width * 0.35,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 8),
                const BaseSkeleton(height: 12, borderRadius: 4),
                const SizedBox(height: 6),
                BaseSkeleton(
                  width: width * 0.6,
                  height: 12,
                  borderRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
