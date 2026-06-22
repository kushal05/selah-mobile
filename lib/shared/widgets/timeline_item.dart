import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Displays a timeline item with a bullet point, text, and timestamp
class TimelineItem extends StatelessWidget {
  final String text;
  final String time;
  final String? author;

  const TimelineItem({
    super.key,
    required this.text,
    required this.time,
    this.author,
  });

  static final _mentionPattern = RegExp(r'(?<=\s|^)@(\w+)');

  Widget _buildStyledText(BuildContext context) {
    final matches = _mentionPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 16));
    }

    final spans = <TextSpan>[];
    var lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppTheme.brandPurple,
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context)
            .style
            .copyWith(fontSize: 16),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 2,
                height: 40,
                color: Colors.grey.shade300,
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStyledText(context),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (author != null) ...[
                      Text(
                        author!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brandPurple,
                        ),
                      ),
                      Text(
                        ' · ',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ],
                    Text(
                      time,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
