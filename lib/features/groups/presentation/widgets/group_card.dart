import 'package:flutter/material.dart';

import '../../../../core/domain/enums/group_enums.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/group_model.dart';

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
              backgroundColor: _groupColor.withValues(alpha: 0.1),
              child: Text(
                group.initials,
                style: TextStyle(
                  fontSize: AppTheme.headingMedium.fontSize,
                  fontWeight: FontWeight.bold,
                  color: _groupColor,
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
                            size: AppTheme.iconSM, color: AppTheme.gray500),
                        const SizedBox(width: AppTheme.spacing4),
                        Text(
                          '$memberCount',
                          style: TextStyle(
                            fontSize: AppTheme.bodySmallStyle.fontSize,
                            color: AppTheme.gray500,
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
                        color: AppTheme.gray600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.gray400),
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
        return Colors.orange;
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
        color: AppTheme.gray100,
        borderRadius: AppTheme.borderRadiusXS,
      ),
      child: Text(
        groupType.displayName,
        style: TextStyle(
          fontSize: AppTheme.tiny.fontSize,
          fontWeight: FontWeight.w500,
          color: AppTheme.gray600,
        ),
      ),
    );
  }
}
