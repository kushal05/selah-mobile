import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Represents formatting applied to a range of text within a block
@immutable
class TextSpanFormat extends Equatable {
  /// Start offset (inclusive)
  final int start;

  /// End offset (exclusive)
  final int end;

  /// Whether text is bold
  final bool isBold;

  /// Whether text is italic
  final bool isItalic;

  /// Whether text is underlined
  final bool isUnderline;

  /// Whether text is strikethrough
  final bool isStrikethrough;

  const TextSpanFormat({
    required this.start,
    required this.end,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
  });

  /// Create a format with no styling
  const TextSpanFormat.none({
    required this.start,
    required this.end,
  })  : isBold = false,
        isItalic = false,
        isUnderline = false,
        isStrikethrough = false;

  /// Whether this format has any active styling
  bool get hasFormatting {
    return isBold || isItalic || isUnderline || isStrikethrough;
  }

  /// Length of the formatted range
  int get length => end - start;

  /// Copy with modifications
  TextSpanFormat copyWith({
    int? start,
    int? end,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    bool? isStrikethrough,
  }) {
    return TextSpanFormat(
      start: start ?? this.start,
      end: end ?? this.end,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      isStrikethrough: isStrikethrough ?? this.isStrikethrough,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'end': end,
      'isBold': isBold,
      'isItalic': isItalic,
      'isUnderline': isUnderline,
      'isStrikethrough': isStrikethrough,
    };
  }

  /// Create from JSON
  factory TextSpanFormat.fromJson(Map<String, dynamic> json) {
    return TextSpanFormat(
      start: json['start'] as int,
      end: json['end'] as int,
      isBold: json['isBold'] as bool? ?? false,
      isItalic: json['isItalic'] as bool? ?? false,
      isUnderline: json['isUnderline'] as bool? ?? false,
      isStrikethrough: json['isStrikethrough'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        start,
        end,
        isBold,
        isItalic,
        isUnderline,
        isStrikethrough,
      ];
}
