import 'package:flutter/material.dart';

import '../../domain/models/bible_search_result.dart';

/// Displays a single Bible verse search result with highlighted matches.
///
/// Shows:
/// - Reference line: "John 3:16 (KJV)"
/// - Verse text with matched terms highlighted
///
/// Calls [onTap] when the card is tapped.
class BibleVerseResultCard extends StatelessWidget {
  final BibleSearchResult result;
  final VoidCallback? onTap;

  const BibleVerseResultCard({
    super.key,
    required this.result,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reference line
            Row(
              children: [
                Icon(
                  Icons.menu_book,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.displayReference,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Verse text with highlighting
            RichText(
              text: TextSpan(
                children: _buildHighlightedSpans(
                  result.highlightedText,
                  baseStyle: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface,
                    height: 1.4,
                  ),
                  highlightStyle: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    backgroundColor:
                        theme.colorScheme.primary.withAlpha(25),
                    height: 1.4,
                  ),
                ),
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Parse FTS5 highlight markers (« and ») into styled TextSpans.
  static List<TextSpan> _buildHighlightedSpans(
    String highlightedText, {
    required TextStyle baseStyle,
    required TextStyle highlightStyle,
  }) {
    if (highlightedText.isEmpty) {
      return [TextSpan(text: '', style: baseStyle)];
    }

    final spans = <TextSpan>[];
    var remaining = highlightedText;

    while (remaining.isNotEmpty) {
      final openIdx = remaining.indexOf(BibleSearchResult.hlOpen);

      if (openIdx < 0) {
        // No more highlights — add remaining text
        spans.add(TextSpan(text: remaining, style: baseStyle));
        break;
      }

      // Add text before the highlight marker
      if (openIdx > 0) {
        spans.add(TextSpan(
          text: remaining.substring(0, openIdx),
          style: baseStyle,
        ));
      }

      // Find closing marker
      final closeIdx = remaining.indexOf(
        BibleSearchResult.hlClose,
        openIdx + 1,
      );

      if (closeIdx < 0) {
        // Malformed — no closing marker, add rest as plain text
        spans.add(TextSpan(
          text: remaining.substring(openIdx + 1),
          style: baseStyle,
        ));
        break;
      }

      // Add highlighted text
      spans.add(TextSpan(
        text: remaining.substring(openIdx + 1, closeIdx),
        style: highlightStyle,
      ));

      remaining = remaining.substring(closeIdx + 1);
    }

    return spans;
  }
}
