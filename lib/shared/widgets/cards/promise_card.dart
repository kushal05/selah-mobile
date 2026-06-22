import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../colored_badge.dart';

class PromiseCard extends StatelessWidget {
  final String reference;
  final String content;
  final int conditionCount;
  final VoidCallback? onTap;

  const PromiseCard({
    super.key,
    required this.reference,
    required this.content,
    this.conditionCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: AppTheme.cardMargin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppTheme.borderRadius2XL,
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppTheme.borderRadius2XL,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTheme.borderRadius2XL,
          child: Padding(
            padding: AppTheme.cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: AppTheme.iconBadgeSM,
                  height: AppTheme.iconBadgeSM,
                  decoration: BoxDecoration(
                    color: AppTheme.rosePink.withValues(alpha: AppTheme.alphaLightMed),
                    borderRadius: AppTheme.borderRadiusLG,
                  ),
                  child: const Icon(
                    Icons.bookmark_outlined,
                    color: AppTheme.rosePink,
                    size: AppTheme.iconLG,
                  ),
                ),
                const SizedBox(width: AppTheme.spacing14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reference,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: AppTheme.rosePink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (content.isNotEmpty) ...[
                        const SizedBox(height: AppTheme.spacing7),
                        Text(
                          content,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.unselectedColor,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (conditionCount > 0) ...[
                        const SizedBox(height: AppTheme.spacing10),
                        ColoredBadge(
                          label: '$conditionCount ${conditionCount == 1 ? 'condition' : 'conditions'}',
                          color: AppTheme.rosePink,
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppTheme.spacing8,
                    top: AppTheme.spacing10,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: AppTheme.iconBase,
                    color: AppTheme.chevronColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
