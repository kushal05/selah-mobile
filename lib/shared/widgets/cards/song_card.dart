import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Card widget for displaying a song in a list
class SongCard extends StatelessWidget {
  final String title;
  final String language;
  final String scale;
  final bool hasChords;
  final bool isFavorite;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;

  const SongCard({
    super.key,
    required this.title,
    required this.language,
    required this.scale,
    required this.hasChords,
    required this.isFavorite,
    required this.preview,
    required this.onTap,
    this.onFavoriteToggle,
  });

  static Widget _badge(String label) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing6, vertical: AppTheme.spacing2),
        decoration: BoxDecoration(
          color: AppTheme.orangeFaint,
          borderRadius: AppTheme.borderRadiusXS,
        ),
        child: Text(label, style: AppTheme.microOrange),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: AppTheme.borderRadiusXL,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.borderRadiusXL,
        child: Padding(
          padding: AppTheme.paddingAllBase,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing10),
                decoration: BoxDecoration(
                  color: AppTheme.orangeFaint,
                  borderRadius: AppTheme.borderRadiusLG,
                ),
                child: const Icon(
                  Icons.music_note,
                  color: AppTheme.orange,
                  size: AppTheme.iconBase,
                ),
              ),
              const SizedBox(width: AppTheme.spacing12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.headingSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppTheme.spacing4),
                    Row(
                      children: [
                        Text(
                          language,
                          style: AppTheme.caption.copyWith(
                            color: AppTheme.gray600,
                          ),
                        ),
                        if (scale.isNotEmpty) ...[
                          const SizedBox(width: AppTheme.spacing8),
                          _badge(scale),
                        ],
                        if (hasChords) ...[
                          const SizedBox(width: AppTheme.spacing8),
                          _badge('Chords'),
                        ],
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.spacing4),
                      Text(
                        preview,
                        style: AppTheme.caption.copyWith(
                          color: AppTheme.unselectedColor,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              if (onFavoriteToggle != null)
                IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.red.shade400 : AppTheme.hintColor,
                    size: AppTheme.iconLG,
                  ),
                  onPressed: onFavoriteToggle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
