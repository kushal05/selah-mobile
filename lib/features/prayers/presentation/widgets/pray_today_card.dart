import 'package:flutter/material.dart';

import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/prayer_metadata_codec.dart';

/// Expandable prayer card used in the Pray Today flow
class PrayTodayCard extends StatefulWidget {
  final PrayerModel prayer;
  final bool isLogged;
  final VoidCallback onLogPress;
  final VoidCallback? onTap;

  const PrayTodayCard({
    super.key,
    required this.prayer,
    required this.isLogged,
    required this.onLogPress,
    this.onTap,
  });

  @override
  State<PrayTodayCard> createState() => _PrayTodayCardState();
}

class _PrayTodayCardState extends State<PrayTodayCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final prayer = widget.prayer;
    final isLogged = widget.isLogged;
    final metadata = decodePrayerMetadata(prayer.category);

    return AnimatedOpacity(
      opacity: isLogged ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLogged
                ? AppTheme.teal.withValues(alpha: 0.5)
                : Colors.grey.shade200,
            width: isLogged ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Status indicator
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isLogged
                            ? AppTheme.teal.withValues(alpha: 0.15)
                            : AppTheme.brandBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isLogged ? Icons.check_circle : Icons.favorite_border,
                        color: isLogged
                            ? AppTheme.teal
                            : AppTheme.brandBlue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title and frequency
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prayer.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              decoration: isLogged
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isLogged
                                  ? Colors.grey.shade500
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            prayer.frequency.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Expand/collapse icon
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),

            // Expanded content
            if (_isExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    if (prayer.content.isNotEmpty) ...[
                      Text(
                        prayer.content.split('\n<!-- updates -->').first.trim(),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Category/tags
                    if (metadata.tags.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: metadata.tags
                            .map((tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.brandBlue
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.brandBlue,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ],

            // Log button
            if (!isLogged)
              Padding(
                padding:
                    const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onLogPress,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Log Prayer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brandBlue,
                      side: const BorderSide(color: AppTheme.brandBlue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),

            // Logged indicator
            if (isLogged)
              Padding(
                padding:
                    const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check, size: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      'Prayed',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
