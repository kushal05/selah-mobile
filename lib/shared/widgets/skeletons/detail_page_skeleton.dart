import 'package:flutter/material.dart';

import 'base_skeleton.dart';

/// Skeleton that mimics a detail page: large title, metadata row, paragraph blocks.
class DetailPageSkeleton extends StatelessWidget {
  final bool hasMetadataRow;

  const DetailPageSkeleton({super.key, this.hasMetadataRow = true});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          BaseSkeleton(width: width * 0.65, height: 24, borderRadius: 6),
          const SizedBox(height: 16),

          // Metadata row
          if (hasMetadataRow) ...[
            Row(
              children: [
                BaseSkeleton(width: width * 0.2, height: 12, borderRadius: 4),
                const SizedBox(width: 16),
                BaseSkeleton(width: width * 0.25, height: 12, borderRadius: 4),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Paragraph blocks
          const BaseSkeleton(height: 14, borderRadius: 4),
          const SizedBox(height: 10),
          const BaseSkeleton(height: 14, borderRadius: 4),
          const SizedBox(height: 10),
          BaseSkeleton(width: width * 0.75, height: 14, borderRadius: 4),
          const SizedBox(height: 20),

          const BaseSkeleton(height: 14, borderRadius: 4),
          const SizedBox(height: 10),
          const BaseSkeleton(height: 14, borderRadius: 4),
          const SizedBox(height: 10),
          BaseSkeleton(width: width * 0.5, height: 14, borderRadius: 4),
          const SizedBox(height: 20),

          const BaseSkeleton(height: 14, borderRadius: 4),
          const SizedBox(height: 10),
          BaseSkeleton(width: width * 0.85, height: 14, borderRadius: 4),
          const SizedBox(height: 10),
          BaseSkeleton(width: width * 0.6, height: 14, borderRadius: 4),
        ],
      ),
    );
  }
}
