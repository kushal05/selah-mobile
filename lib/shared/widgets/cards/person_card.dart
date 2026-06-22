import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Displays a person card in the people list
class PersonCard extends StatelessWidget {
  final String name;
  final String relation;
  final VoidCallback? onTap;

  const PersonCard({
    super.key,
    required this.name,
    required this.relation,
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
          color: Colors.white,
          borderRadius: AppTheme.borderRadiusXL,
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.teal.withValues(alpha: AppTheme.alphaLightMed),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.teal,
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  Text(
                    relation,
                    style: AppTheme.bodyBase.copyWith(
                      color: AppTheme.gray600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppTheme.hintColor,
            ),
          ],
        ),
      ),
    );
  }
}
