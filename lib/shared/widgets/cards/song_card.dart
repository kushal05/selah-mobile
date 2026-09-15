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

  static Widget _badge(String label, Brightness brightness) {
    // Raw orange on its own 10% tint is 1.90:1 — resolve to the variant
    // tuned for exactly this background.
    final fg = AppTheme.accentOnTintFor(AppTheme.orange, brightness);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing6, vertical: AppTheme.spacing2),
      decoration: BoxDecoration(
        color: AppTheme.orangeFaint,
        borderRadius: AppTheme.borderRadiusXS,
      ),
      child: Text(label, style: AppTheme.tiny.copyWith(color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardTheme.color,
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
                child: Icon(
                  Icons.music_note,
                  color: AppTheme.accentOnTintFor(
                      AppTheme.orange, Theme.of(context).brightness),
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
                    // Wrap, not Row: language plus two badges overflows once
                    // the text scale grows, and none of the three can shrink.
                    Wrap(
                      spacing: AppTheme.spacing8,
                      runSpacing: AppTheme.spacing4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          language,
                          style: AppTheme.caption.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (scale.isNotEmpty) _badge(scale, Theme.of(context).brightness),
                        if (hasChords) _badge('Chords', Theme.of(context).brightness),
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.spacing4),
                      Text(
                        preview,
                        style: AppTheme.caption.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  tooltip: isFavorite ? 'Remove from favourites' : 'Add to favourites',
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.red.shade400 : Theme.of(context).colorScheme.onSurfaceVariant,
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
