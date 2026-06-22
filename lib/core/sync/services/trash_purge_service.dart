import '../repositories/folder_repository.dart';
import '../repositories/note_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/prayer_repository.dart';
import '../repositories/preacher_repository.dart';
import '../repositories/promise_repository.dart';
import '../repositories/song_repository.dart';
import '../repositories/tag_repository.dart';
import '../../testing/test_clock.dart';

/// Permanently deletes trashed items older than [purgeDays].
///
/// Runs on app startup. Trashed items are kept for 30 days, after which
/// they are permanently soft-deleted (deleted=1) via the existing delete flow.
class TrashPurgeService {
  static const int purgeDays = 30;

  final NoteRepository _noteRepo;
  final FolderRepository _folderRepo;
  final PrayerRepository _prayerRepo;
  final PromiseRepository _promiseRepo;
  final PersonRepository _personRepo;
  final SongRepository _songRepo;
  final PreacherRepository _preacherRepo;
  final TagRepository _tagRepo;
  final String _userId;

  TrashPurgeService({
    required NoteRepository noteRepo,
    required FolderRepository folderRepo,
    required PrayerRepository prayerRepo,
    required PromiseRepository promiseRepo,
    required PersonRepository personRepo,
    required SongRepository songRepo,
    required PreacherRepository preacherRepo,
    required TagRepository tagRepo,
    required String userId,
  })  : _noteRepo = noteRepo,
        _folderRepo = folderRepo,
        _prayerRepo = prayerRepo,
        _promiseRepo = promiseRepo,
        _personRepo = personRepo,
        _songRepo = songRepo,
        _preacherRepo = preacherRepo,
        _tagRepo = tagRepo,
        _userId = userId;

  /// Purge all trashed items older than 30 days. Returns count of purged items.
  Future<int> purgeExpiredItems() async {
    final cutoff = TestClock.now() - (purgeDays * 24 * 60 * 60 * 1000);
    var count = 0;

    // Notes
    final trashedNotes = await _noteRepo.getTrashedNotes(_userId);
    for (final note in trashedNotes) {
      if (note.trashedAt != null && note.trashedAt! < cutoff) {
        await _noteRepo.deleteNote(note.id);
        count++;
      }
    }

    // Folders
    final trashedFolders = await _folderRepo.getTrashedFolders(_userId);
    for (final folder in trashedFolders) {
      if (folder.trashedAt != null && folder.trashedAt! < cutoff) {
        await _folderRepo.deleteFolder(folder.id);
        count++;
      }
    }

    // Prayers
    final trashedPrayers = await _prayerRepo.getTrashedPrayers(_userId);
    for (final prayer in trashedPrayers) {
      if (prayer.trashedAt != null && prayer.trashedAt! < cutoff) {
        await _prayerRepo.deletePrayer(prayer.id);
        count++;
      }
    }

    // Promises
    final trashedPromises = await _promiseRepo.getTrashedPromises(_userId);
    for (final promise in trashedPromises) {
      if (promise.trashedAt != null && promise.trashedAt! < cutoff) {
        await _promiseRepo.deletePromise(promise.id);
        count++;
      }
    }

    // People
    final trashedPeople = await _personRepo.getTrashedPeople(_userId);
    for (final person in trashedPeople) {
      if (person.trashedAt != null && person.trashedAt! < cutoff) {
        await _personRepo.deletePerson(person.id);
        count++;
      }
    }

    // Songs
    final trashedSongs = await _songRepo.getTrashedSongs(_userId);
    for (final song in trashedSongs) {
      if (song.trashedAt != null && song.trashedAt! < cutoff) {
        await _songRepo.deleteSong(song.id);
        count++;
      }
    }

    // Preachers
    final trashedPreachers = await _preacherRepo.getTrashedPreachers(_userId);
    for (final preacher in trashedPreachers) {
      if (preacher.trashedAt != null && preacher.trashedAt! < cutoff) {
        await _preacherRepo.deletePreacher(preacher.id);
        count++;
      }
    }

    // Tags
    final trashedTags = await _tagRepo.getTrashedTags(_userId);
    for (final tag in trashedTags) {
      if (tag.trashedAt != null && tag.trashedAt! < cutoff) {
        await _tagRepo.deleteTag(tag.id);
        count++;
      }
    }

    return count;
  }
}
