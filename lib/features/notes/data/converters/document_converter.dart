import 'dart:convert';

import '../../domain/models/editor_document.dart';

/// Converter for EditorDocument to/from JSON string
class DocumentConverter {
  /// Convert EditorDocument to JSON string
  static String toJsonString(EditorDocument document) {
    return jsonEncode(document.toJson());
  }

  /// Convert JSON string to EditorDocument
  static EditorDocument fromJsonString(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return EditorDocument.fromJson(json);
    } catch (e) {
      // If JSON is malformed, return empty document
      return EditorDocument.empty();
    }
  }

  /// Convert EditorDocument to Map
  static Map<String, dynamic> toMap(EditorDocument document) {
    return document.toJson();
  }

  /// Convert Map to EditorDocument
  static EditorDocument fromMap(Map<String, dynamic> map) {
    try {
      return EditorDocument.fromJson(map);
    } catch (e) {
      // If map is malformed, return empty document
      return EditorDocument.empty();
    }
  }
}
