import 'package:flutter/material.dart';

import '../../../../core/domain/enums/group_enums.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/group_model.dart';
import '../../../../core/theme/theme_colors.dart';

/// Displays a group in the groups list
class GroupCard extends StatelessWidget {
  final GroupModel group;
  final int? memberCount;
  final VoidCallback? onTap;

  const GroupCard({
    super.key,
    required this.group,
    this.memberCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacing12),
        padding: AppTheme.paddingAllBase,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: AppTheme.borderRadiusXL,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              // The raw brand colour tints the avatar; the initials on top of
              // it need the tuned one. Raw teal on its own 10% tint measures
              // 1.81:1 on the light ground and ministryPurple 3.67:1 on the
              // dark — the initials are the only thing identifying the group.
              backgroundColor: _groupColor.withValues(alpha: 0.1),
              child: Text(
                group.initials,
                style: TextStyle(
                  fontSize: AppTheme.headingMedium.fontSize,
                  fontWeight: FontWeight.bold,
                  color: context.accentInk(_groupColor),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: TextStyle(
                      fontSize: AppTheme.headingSmall.fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  Row(
                    children: [
                      _GroupTypeBadge(groupType: group.groupType),
                      if (memberCount != null) ...[
                        const SizedBox(width: AppTheme.spacing8),
                        Icon(Icons.people_outline,
                            size: AppTheme.iconSM, color: context.mutedText),
                        const SizedBox(width: AppTheme.spacing4),
                        Text(
                          '$memberCount',
                          style: TextStyle(
                            fontSize: AppTheme.bodySmallStyle.fontSize,
                            color: context.mutedText,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (group.description.isNotEmpty) ...[
                    const SizedBox(height: AppTheme.spacing4),
                    Text(
                      group.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTheme.bodySmallStyle.fontSize,
                        color: context.mutedText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: context.hintText),
          ],
        ),
      ),
    );
  }

  Color get _groupColor {
    switch (group.groupType) {
      case GroupType.church:
        return AppTheme.teal;
      case GroupType.smallGroup:
        return AppTheme.teal;
      case GroupType.prayerGroup:
        return AppTheme.coral;
      case GroupType.ministry:
        return AppTheme.ministryPurple;
      case GroupType.other:
        // AppTheme.orange, not Colors.orange: only design-system tokens have
        // an accentOnDark/onLight pair for accentInk to reach for.
        return AppTheme.orange;
    }
  }
}

class _GroupTypeBadge extends StatelessWidget {
  final GroupType groupType;
  const _GroupTypeBadge({required this.groupType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing8, vertical: AppTheme.spacing2),
      decoration: BoxDecoration(
        color: context.subtleFill,
        borderRadius: AppTheme.borderRadiusXS,
      ),
      child: Text(
        groupType.displayName,
        style: TextStyle(
          fontSize: AppTheme.tiny.fontSize,
          fontWeight: FontWeight.w500,
          color: context.mutedText,
        ),
      ),
    );
  }
}
