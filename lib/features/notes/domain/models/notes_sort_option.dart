/// Sort options for the notes list.
///
/// Lives outside the screen so the screen's UI-state provider can reference it
/// without importing the 2,000-line widget file back.
///
/// [label] is a non-localised fallback, kept for logging and debug output.
/// Anything the user reads goes through `_sortLabel` in the notes screen,
/// which resolves `notesSortLastEdited` and friends from the ARB.
enum NotesSortOption {
  lastEdited('Last Edited'),
  title('Title (A-Z)'),
  createdDate('Created Date');

  final String label;
  const NotesSortOption(this.label);
}
