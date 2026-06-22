import '../../../../core/sync/models/song_model.dart';
import '../../../notes/domain/models/note.dart';
import '../../../notes/domain/models/note_section.dart';

/// Extract a lyric snippet around the first match of [query] in the song lyrics.
String getLyricSnippet(SongModel song, String query) {
  if (query.isEmpty || song.lyrics.isEmpty) return '';
  final lowerLyrics = song.lyrics.toLowerCase();
  final lowerQuery = query.toLowerCase();
  final idx = lowerLyrics.indexOf(lowerQuery);
  if (idx < 0) return '';

  final start = (idx - 20).clamp(0, song.lyrics.length);
  final end = (idx + query.length + 40).clamp(0, song.lyrics.length);
  final raw = song.lyrics.substring(start, end).replaceAll('\n', ' ');
  return '${start > 0 ? '...' : ''}$raw${end < song.lyrics.length ? '...' : ''}';
}

/// Build subtitle for a note search result, showing section label when
/// the match is in Personal Application or Prayer section.
String getNoteSubtitle(Note note, String query) {
  if (query.isEmpty) return 'Note';
  final lowerQuery = query.toLowerCase();

  // Check if title matches — if so, no section label needed
  if (note.title.toLowerCase().contains(lowerQuery)) return 'Note';

  // Check subsections for content matches
  for (final section in [NoteSection.personalApplication, NoteSection.prayer]) {
    final sectionBlocks = note.document.getBlocksForSection(section);
    for (final block in sectionBlocks) {
      if (block.content.toLowerCase().contains(lowerQuery)) {
        return section.searchLabel;
      }
    }
  }

  return 'Note';
}
