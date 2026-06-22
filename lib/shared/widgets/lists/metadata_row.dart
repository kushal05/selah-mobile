import 'package:flutter/material.dart';

/// Displays metadata information (e.g., date, preacher) as icon+text pairs
class MetadataRow extends StatelessWidget {
  final String? date;
  final String? preacher;
  final List<String>? tags;

  const MetadataRow({
    super.key,
    this.date,
    this.preacher,
    this.tags,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (date != null) {
      items.add(MetadataItem(icon: Icons.calendar_today, text: date!));
    }

    if (preacher != null) {
      items.add(MetadataItem(icon: Icons.person, text: preacher!));
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: items,
    );
  }
}

/// A single metadata item displaying an icon and text.
class MetadataItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const MetadataItem({
    super.key,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
