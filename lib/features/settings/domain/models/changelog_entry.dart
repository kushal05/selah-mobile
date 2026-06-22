class ChangeItem {
  final String type; // "feature" | "improvement" | "fix"
  final String description;

  const ChangeItem({required this.type, required this.description});

  factory ChangeItem.fromJson(Map<String, dynamic> json) => ChangeItem(
        type: json['type'] as String? ?? 'feature',
        description: json['description'] as String? ?? '',
      );
}

class ChangelogEntry {
  final String id;
  final String version;
  final String releaseDate;
  final List<ChangeItem> changes;
  final int sortOrder;

  const ChangelogEntry({
    required this.id,
    required this.version,
    required this.releaseDate,
    required this.changes,
    required this.sortOrder,
  });

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) => ChangelogEntry(
        id: json['id'] as String? ?? '',
        version: json['version'] as String? ?? '',
        releaseDate: json['releaseDate'] as String? ?? '',
        changes: (json['changes'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(ChangeItem.fromJson)
            .toList(),
        sortOrder: json['sortOrder'] as int? ?? 0,
      );
}
