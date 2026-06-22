import 'dart:convert';

const _jsonPrefix = 'meta:';

class PrayerMetadata {
  final List<String> tags;
  final List<String> linkedPeopleIds;
  final int? reminderAtMillis;

  const PrayerMetadata({
    this.tags = const [],
    this.linkedPeopleIds = const [],
    this.reminderAtMillis,
  });

  bool get hasReminder => reminderAtMillis != null;

  Map<String, dynamic> toJson() => {
        'tags': tags,
        'linkedPeopleIds': linkedPeopleIds,
        // reminderAtMillis is no longer written here — stored in prayers.reminderAt column.
        // Kept in fromJson for backward compatibility with older data.
      };

  factory PrayerMetadata.fromJson(Map<String, dynamic> json) {
    return PrayerMetadata(
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where((t) => t.isNotEmpty)
          .toList(),
      linkedPeopleIds: (json['linkedPeopleIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList(),
      reminderAtMillis: json['reminderAtMillis'] as int?,
    );
  }
}

String encodePrayerMetadata(PrayerMetadata metadata) {
  return '$_jsonPrefix${jsonEncode(metadata.toJson())}';
}

PrayerMetadata decodePrayerMetadata(String? rawCategory) {
  if (rawCategory == null || rawCategory.trim().isEmpty) {
    return const PrayerMetadata();
  }

  final input = rawCategory.trim();

  if (input.startsWith(_jsonPrefix)) {
    try {
      final decoded =
          jsonDecode(input.substring(_jsonPrefix.length)) as Map<String, dynamic>;
      return PrayerMetadata.fromJson(decoded);
    } catch (_) {
      return const PrayerMetadata();
    }
  }

  // Backward compatibility with older string formats:
  // 1) "tag1, tag2||personId1, personId2"
  // 2) "tag1, tag2"
  if (input.contains('||')) {
    final parts = input.split('||');
    final tags = parts.first
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final linked = parts.length > 1
        ? parts[1]
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    return PrayerMetadata(tags: tags, linkedPeopleIds: linked);
  }

  final tags = input
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  return PrayerMetadata(tags: tags);
}

