import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents the canonical cursor position in the editor
/// This is the source of truth for cursor state, NOT Flutter's TextSelection
@immutable
class EditorCursor extends Equatable {
  /// ID of the block containing the cursor
  final String blockId;

  /// Character offset within the block (0-based)
  final int offset;

  /// Text affinity (for ambiguous positions like line breaks)
  final TextAffinity affinity;

  const EditorCursor({
    required this.blockId,
    required this.offset,
    this.affinity = TextAffinity.downstream,
  });

  /// Create a cursor at the start of a block
  const EditorCursor.atStart(this.blockId)
      : offset = 0,
        affinity = TextAffinity.downstream;

  /// Create a cursor at the end of a block
  const EditorCursor.atEnd(this.blockId, int length)
      : offset = length,
        affinity = TextAffinity.upstream;

  /// Copy with modifications
  EditorCursor copyWith({
    String? blockId,
    int? offset,
    TextAffinity? affinity,
  }) {
    return EditorCursor(
      blockId: blockId ?? this.blockId,
      offset: offset ?? this.offset,
      affinity: affinity ?? this.affinity,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'blockId': blockId,
      'offset': offset,
      'affinity': affinity == TextAffinity.upstream ? 'upstream' : 'downstream',
    };
  }

  /// Create from JSON
  factory EditorCursor.fromJson(Map<String, dynamic> json) {
    return EditorCursor(
      blockId: json['blockId'] as String,
      offset: json['offset'] as int,
      affinity: json['affinity'] == 'upstream'
          ? TextAffinity.upstream
          : TextAffinity.downstream,
    );
  }

  @override
  List<Object?> get props => [blockId, offset, affinity];

  @override
  String toString() => 'EditorCursor(blockId: $blockId, offset: $offset, affinity: $affinity)';
}

/// Represents a selection range in the editor
/// Can span multiple blocks
@immutable
class EditorSelection extends Equatable {
  /// Start position of selection (anchor)
  final EditorCursor anchor;

  /// End position of selection (focus/cursor)
  final EditorCursor focus;

  const EditorSelection({
    required this.anchor,
    required this.focus,
  });

  /// Create a collapsed selection (cursor only, no range)
  const EditorSelection.collapsed(EditorCursor cursor)
      : anchor = cursor,
        focus = cursor;

  /// Whether the selection is collapsed (no range selected)
  bool get isCollapsed => anchor == focus;

  /// Whether the selection spans multiple blocks
  bool get spansMultipleBlocks => anchor.blockId != focus.blockId;

  /// Copy with modifications
  EditorSelection copyWith({
    EditorCursor? anchor,
    EditorCursor? focus,
  }) {
    return EditorSelection(
      anchor: anchor ?? this.anchor,
      focus: focus ?? this.focus,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'anchor': anchor.toJson(),
      'focus': focus.toJson(),
    };
  }

  /// Create from JSON
  factory EditorSelection.fromJson(Map<String, dynamic> json) {
    return EditorSelection(
      anchor: EditorCursor.fromJson(json['anchor'] as Map<String, dynamic>),
      focus: EditorCursor.fromJson(json['focus'] as Map<String, dynamic>),
    );
  }

  @override
  List<Object?> get props => [anchor, focus];

  @override
  String toString() => 'EditorSelection(anchor: $anchor, focus: $focus)';
}
