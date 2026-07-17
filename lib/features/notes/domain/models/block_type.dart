/// Block types supported by the editor
enum BlockType {
  /// Heading level 1 (28sp bold)
  heading1,

  /// Heading level 2 (24sp bold)
  heading2,

  /// Heading level 3 (20sp bold)
  heading3,

  /// Standard paragraph
  paragraph,

  /// Bullet list item
  bulletList,

  /// Numbered list item
  numberedList,

  /// Checkbox list item
  checkbox,

  /// Block quote (indented, accented left border)
  quote,

  /// Code block (monospace, filled background)
  code,

  /// Table (non-editable card; content is JSON-encoded [NoteTable])
  table,

  /// Bible reference (non-editable card)
  bibleReference,
}

extension BlockTypeExtension on BlockType {
  /// Display name for the block type
  String get displayName {
    switch (this) {
      case BlockType.heading1:
        return 'Heading 1';
      case BlockType.heading2:
        return 'Heading 2';
      case BlockType.heading3:
        return 'Heading 3';
      case BlockType.paragraph:
        return 'Paragraph';
      case BlockType.bulletList:
        return 'Bullet List';
      case BlockType.numberedList:
        return 'Numbered List';
      case BlockType.checkbox:
        return 'Checkbox';
      case BlockType.quote:
        return 'Quote';
      case BlockType.code:
        return 'Code Block';
      case BlockType.table:
        return 'Table';
      case BlockType.bibleReference:
        return 'Bible Reference';
    }
  }

  /// Whether this block type is a list type
  bool get isList {
    return this == BlockType.bulletList ||
        this == BlockType.numberedList ||
        this == BlockType.checkbox;
  }

  /// Whether this block type is a heading
  bool get isHeading {
    return this == BlockType.heading1 ||
        this == BlockType.heading2 ||
        this == BlockType.heading3;
  }

  /// Whether this block stores structured JSON in `content` and renders as a
  /// non-editable card.
  ///
  /// Atomic blocks have no caret and their `content` is NOT display text, so it
  /// must never be concatenated with surrounding text (doing so both leaks JSON
  /// into the note and destroys the block's data).
  bool get isAtomic {
    return this == BlockType.table || this == BlockType.bibleReference;
  }
}
