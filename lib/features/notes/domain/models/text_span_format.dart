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

  /// Whether text is rendered as inline code (monospace)
  final bool isCode;

  /// Link target URL. Non-null means this range is a hyperlink.
  final String? link;

  const TextSpanFormat({
    required this.start,
    required this.end,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
    this.isCode = false,
    this.link,
  });

  /// Create a format with no styling
  const TextSpanFormat.none({
    required this.start,
    required this.end,
  })  : isBold = false,
        isItalic = false,
        isUnderline = false,
        isStrikethrough = false,
        isCode = false,
        link = null;

  /// Whether this format has any active styling
  bool get hasFormatting {
    return isBold ||
        isItalic ||
        isUnderline ||
        isStrikethrough ||
        isCode ||
        (link != null && link!.isNotEmpty);
  }

  /// Length of the formatted range
  int get length => end - start;

  /// Copy with modifications
  ///
  /// [link] uses a sentinel so an explicit `null` can clear the link while
  /// omitting it preserves the existing value.
  TextSpanFormat copyWith({
    int? start,
    int? end,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    bool? isStrikethrough,
    bool? isCode,
    Object? link = _sentinel,
  }) {
    return TextSpanFormat(
      start: start ?? this.start,
      end: end ?? this.end,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderline: isUnderline ?? this.isUnderline,
      isStrikethrough: isStrikethrough ?? this.isStrikethrough,
      isCode: isCode ?? this.isCode,
      link: identical(link, _sentinel) ? this.link : link as String?,
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
      // Only emit the newer attributes when set to keep payloads small and
      // backward-compatible with clients that don't understand them.
      if (isCode) 'isCode': isCode,
      if (link != null && link!.isNotEmpty) 'link': link,
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
      isCode: json['isCode'] as bool? ?? false,
      link: json['link'] as String?,
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
        isCode,
        link,
      ];
}

/// Sentinel for [TextSpanFormat.copyWith] to distinguish "not passed" from an
/// explicit `null` link.
const Object _sentinel = Object();
