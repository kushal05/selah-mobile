/// Sections within a note
///
/// Each note has three sections:
/// - [main] — The primary content area
/// - [personalApplication] — "How does this apply to my life?"
/// - [prayer] — "Write a prayer based on this note..."
///
/// Blocks are tagged with a section so they sync independently.
/// Editing one section never affects another.
enum NoteSection {
  main,
  personalApplication,
  prayer;

  String toDbValue() => name;

  static NoteSection fromDbValue(String value) {
    return NoteSection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NoteSection.main,
    );
  }
}

extension NoteSectionExtension on NoteSection {
  /// Display title shown in the editor
  String get displayTitle {
    switch (this) {
      case NoteSection.main:
        return 'Content';
      case NoteSection.personalApplication:
        return 'Personal Application';
      case NoteSection.prayer:
        return 'Prayer';
    }
  }

  /// Placeholder text for empty sections
  String get placeholder {
    switch (this) {
      case NoteSection.main:
        return '';
      case NoteSection.personalApplication:
        return 'How does this apply to my life?';
      case NoteSection.prayer:
        return 'Write a prayer based on this note...';
    }
  }

  /// Label shown in search results when a match is found in this section
  String get searchLabel {
    switch (this) {
      case NoteSection.main:
        return 'Note';
      case NoteSection.personalApplication:
        return 'Personal Application';
      case NoteSection.prayer:
        return 'Prayer';
    }
  }
}
