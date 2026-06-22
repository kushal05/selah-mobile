import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Nested reference object identifying the Bible location
@immutable
class BibleVerseReference extends Equatable {
  final String book;
  final int chapter;
  final List<int> verses;
  final String version;

  const BibleVerseReference({
    required this.book,
    required this.chapter,
    required this.verses,
    required this.version,
  });

  Map<String, dynamic> toJson() {
    return {
      'book': book,
      'chapter': chapter,
      'verses': verses,
      'version': version,
    };
  }

  factory BibleVerseReference.fromJson(Map<String, dynamic> json) {
    return BibleVerseReference(
      book: json['book'] as String? ?? '',
      chapter: json['chapter'] as int? ?? 1,
      verses: (json['verses'] as List<dynamic>?)
              ?.map((v) => v as int)
              .toList() ??
          [1],
      version: json['version'] as String? ?? 'kjv',
    );
  }

  BibleVerseReference copyWith({
    String? book,
    int? chapter,
    List<int>? verses,
    String? version,
  }) {
    return BibleVerseReference(
      book: book ?? this.book,
      chapter: chapter ?? this.chapter,
      verses: verses ?? this.verses,
      version: version ?? this.version,
    );
  }

  @override
  List<Object?> get props => [book, chapter, verses, version];
}

/// Individual verse with its number and full text content
@immutable
class BibleVerseText extends Equatable {
  final int verse;
  final String content;

  const BibleVerseText({
    required this.verse,
    required this.content,
  });

  Map<String, dynamic> toJson() {
    return {
      'verse': verse,
      'content': content,
    };
  }

  factory BibleVerseText.fromJson(Map<String, dynamic> json) {
    return BibleVerseText(
      verse: json['verse'] as int? ?? 1,
      content: json['content'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [verse, content];
}

/// Display configuration for how the verse block renders
@immutable
class BibleVerseDisplay extends Equatable {
  final bool showVerseNumbers;
  final String style;

  const BibleVerseDisplay({
    this.showVerseNumbers = true,
    this.style = 'quote',
  });

  Map<String, dynamic> toJson() {
    return {
      'showVerseNumbers': showVerseNumbers,
      'style': style,
    };
  }

  factory BibleVerseDisplay.fromJson(Map<String, dynamic> json) {
    return BibleVerseDisplay(
      showVerseNumbers: json['showVerseNumbers'] as bool? ?? true,
      style: json['style'] as String? ?? 'quote',
    );
  }

  BibleVerseDisplay copyWith({
    bool? showVerseNumbers,
    String? style,
  }) {
    return BibleVerseDisplay(
      showVerseNumbers: showVerseNumbers ?? this.showVerseNumbers,
      style: style ?? this.style,
    );
  }

  @override
  List<Object?> get props => [showVerseNumbers, style];
}

/// Data model for a Bible verse block stored in an EditorBlock's content.
///
/// Stores the full verse text inline for offline rendering and immutability.
/// Once inserted, verse text is never auto-updated even if Bible data changes.
///
/// Supports backward-compatible deserialization from the old flat format:
///   {book, chapter, verseStart, verseEnd?, version, text, reference, pending}
/// And the new structured format:
///   {reference: {...}, text: [...], source, insertedAt, display: {...}, pending}
@immutable
class BibleReference extends Equatable {
  final BibleVerseReference reference;
  final List<BibleVerseText> text;
  final String source;
  final int insertedAt;
  final BibleVerseDisplay display;
  final bool pending;

  const BibleReference({
    required this.reference,
    required this.text,
    this.source = 'local',
    this.insertedAt = 0,
    this.display = const BibleVerseDisplay(),
    this.pending = false,
  });

  /// Create a fallback/error reference
  factory BibleReference.empty() {
    return const BibleReference(
      reference: BibleVerseReference(
        book: '',
        chapter: 1,
        verses: [1],
        version: 'kjv',
      ),
      text: [],
      pending: true,
    );
  }

  /// Display reference string (e.g., "John 3:16-18 (KJV)")
  String get displayReference {
    final ref = reference;
    String verseStr;
    if (ref.verses.isEmpty) {
      verseStr = '1';
    } else if (ref.verses.length == 1) {
      verseStr = '${ref.verses.first}';
    } else {
      verseStr = '${ref.verses.first}-${ref.verses.last}';
    }
    return '${ref.book} ${ref.chapter}:$verseStr (${ref.version.toUpperCase()})';
  }

  /// Full concatenated text of all verses (for copy, share, search)
  String get fullText {
    return text.map((v) => v.content).join(' ');
  }

  /// Convert to JSON (always writes new format)
  Map<String, dynamic> toJson() {
    return {
      'reference': reference.toJson(),
      'text': text.map((v) => v.toJson()).toList(),
      'source': source,
      'insertedAt': insertedAt,
      'display': display.toJson(),
      'pending': pending,
    };
  }

  /// Create from JSON — handles both old and new formats.
  ///
  /// Old format detection: presence of `verseStart` key (int).
  /// New format detection: presence of `reference` key (Map).
  factory BibleReference.fromJson(Map<String, dynamic> json) {
    // New format: reference is a nested Map
    if (json['reference'] is Map<String, dynamic>) {
      return BibleReference(
        reference: BibleVerseReference.fromJson(
          json['reference'] as Map<String, dynamic>,
        ),
        text: (json['text'] as List<dynamic>?)
                ?.map((v) => BibleVerseText.fromJson(v as Map<String, dynamic>))
                .toList() ??
            [],
        source: json['source'] as String? ?? 'local',
        insertedAt: json['insertedAt'] as int? ?? 0,
        display: json['display'] is Map<String, dynamic>
            ? BibleVerseDisplay.fromJson(
                json['display'] as Map<String, dynamic>)
            : const BibleVerseDisplay(),
        pending: json['pending'] as bool? ?? false,
      );
    }

    // Old format: flat structure with verseStart/verseEnd
    final book = json['book'] as String? ?? '';
    final chapter = json['chapter'] as int? ?? 1;
    final verseStart = json['verseStart'] as int? ?? 1;
    final verseEnd = json['verseEnd'] as int?;
    final version = json['version'] as String? ?? 'kjv';
    final oldText = json['text'] as String? ?? '';
    final pendingFlag = json['pending'] as bool? ?? false;

    // Build verses list from range
    final List<int> verses;
    if (verseEnd != null && verseEnd != verseStart) {
      verses = List.generate(verseEnd - verseStart + 1, (i) => verseStart + i);
    } else {
      verses = [verseStart];
    }

    // Old format stored concatenated text — cannot split into individual verses.
    // Store as single entry tagged with the start verse.
    final List<BibleVerseText> verseTexts;
    if (oldText.isNotEmpty) {
      verseTexts = [BibleVerseText(verse: verseStart, content: oldText)];
    } else {
      verseTexts = [];
    }

    return BibleReference(
      reference: BibleVerseReference(
        book: book,
        chapter: chapter,
        verses: verses,
        version: version,
      ),
      text: verseTexts,
      source: 'api',
      insertedAt: 0,
      display: const BibleVerseDisplay(showVerseNumbers: false, style: 'quote'),
      pending: pendingFlag,
    );
  }

  BibleReference copyWith({
    BibleVerseReference? reference,
    List<BibleVerseText>? text,
    String? source,
    int? insertedAt,
    BibleVerseDisplay? display,
    bool? pending,
  }) {
    return BibleReference(
      reference: reference ?? this.reference,
      text: text ?? this.text,
      source: source ?? this.source,
      insertedAt: insertedAt ?? this.insertedAt,
      display: display ?? this.display,
      pending: pending ?? this.pending,
    );
  }

  @override
  List<Object?> get props =>
      [reference, text, source, insertedAt, display, pending];

  @override
  String toString() => 'BibleReference($displayReference)';
}
