import 'package:flutter/material.dart';

import 'base_skeleton.dart';

/// Skeleton that mimics a ListTile: leading circle, title line, subtitle line.
class ListTileSkeleton extends StatelessWidget {
  final bool hasLeading;
  final bool hasTrailing;

  const ListTileSkeleton({
    super.key,
    this.hasLeading = true,
    this.hasTrailing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (hasLeading) ...[
            const BaseSkeleton.circle(size: 40),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BaseSkeleton(
                  width: MediaQuery.of(context).size.width * 0.45,
                  height: 14,
                  borderRadius: 4,
                ),
                const SizedBox(height: 8),
                BaseSkeleton(
                  width: MediaQuery.of(context).size.width * 0.3,
                  height: 12,
                  borderRadius: 4,
                ),
              ],
            ),
          ),
          if (hasTrailing)
            const BaseSkeleton(width: 24, height: 24, borderRadius: 4),
        ],
      ),
    );
  }
}

/// A column of [count] ListTileSkeletons for list loading states.
class ListTileSkeletonList extends StatelessWidget {
  final int count;
  final bool hasLeading;

  const ListTileSkeletonList({
    super.key,
    this.count = 6,
    this.hasLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, _) => ListTileSkeleton(hasLeading: hasLeading),
    );
  }
}
