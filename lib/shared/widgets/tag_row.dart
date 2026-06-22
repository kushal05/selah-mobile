import 'package:flutter/material.dart';

/// Displays a horizontal row of tags
class TagRow extends StatelessWidget {
  final List<String> tags;

  const TagRow({super.key, required this.tags});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags
          .map((tag) => Chip(
                label: Text(
                  tag,
                  style: const TextStyle(fontSize: 12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                side: BorderSide.none,
              ))
          .toList(),
    );
  }
}
