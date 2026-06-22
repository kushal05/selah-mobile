import 'dart:convert';

const promiseConditionsSeparator = '\n<!-- conditions -->\n';

class PromiseConditionItem {
  /// Null for newly added items, set for items loaded from the DB.
  final String? id;
  final String description;
  final String? notes;
  final String status;

  const PromiseConditionItem({
    this.id,
    required this.description,
    this.notes,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'notes': notes,
        'status': status,
      };

  factory PromiseConditionItem.fromJson(Map<String, dynamic> json) {
    return PromiseConditionItem(
      description: json['description'] as String? ?? '',
      notes: json['notes'] as String?,
      status: (json['status'] as String? ?? 'ACTIVE').toUpperCase(),
    );
  }
}

({String userNotes, List<PromiseConditionItem> conditions})
    parsePromiseNotesWithConditions(String notes) {
  final idx = notes.indexOf(promiseConditionsSeparator);
  if (idx == -1) {
    return (userNotes: notes, conditions: <PromiseConditionItem>[]);
  }

  final userNotes = notes.substring(0, idx);
  final jsonStr = notes.substring(idx + promiseConditionsSeparator.length);
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) {
      return (userNotes: notes, conditions: <PromiseConditionItem>[]);
    }

    final items = decoded
        .whereType<Map>()
        .map((e) => PromiseConditionItem.fromJson(
            Map<String, dynamic>.from(e)))
        .toList();
    return (userNotes: userNotes, conditions: items);
  } catch (_) {
    return (userNotes: notes, conditions: <PromiseConditionItem>[]);
  }
}

int countPromiseConditions(String notes) {
  final idx = notes.indexOf(promiseConditionsSeparator);
  if (idx == -1) return 0;
  final jsonStr = notes.substring(idx + promiseConditionsSeparator.length);
  try {
    final decoded = jsonDecode(jsonStr);
    return decoded is List ? decoded.length : 0;
  } catch (_) {
    return 0;
  }
}

String encodePromiseNotesWithConditions(
  String userNotes,
  List<PromiseConditionItem> conditions,
) {
  if (conditions.isEmpty) return userNotes;
  final json = jsonEncode(conditions.map((c) => c.toJson()).toList());
  return '$userNotes$promiseConditionsSeparator$json';
}
