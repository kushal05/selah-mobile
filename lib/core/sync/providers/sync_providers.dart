import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/app_database.dart';
import '../../database/migration/notes_migration_service.dart';
import '../../database/migration/promise_inline_migration_service.dart';
import '../../database/services/note_block_fts_service.dart';
import '../../database/sync_database.dart';
import '../../domain/enums/prayer_enums.dart';
import '../../config/app_config.dart';
import '../../config/remote/remote_config_keys.dart';
import '../../config/remote/remote_config_providers.dart';
import '../config/sync_config.dart';
import '../engine/sync_state_machine.dart';
import '../models/folder_model.dart';
import '../models/note_model.dart';
import '../models/prayer_model.dart';
import '../models/promise_model.dart';
import '../models/person_model.dart';
import '../models/song_model.dart';
import '../models/prayer_log_model.dart';
import '../models/user_profile_model.dart';
import '../models/user_stats_model.dart';
import '../models/friendship_model.dart';
import '../models/friend_request_model.dart';
import '../models/blocked_user_model.dart';
import '../models/shared_prayer_model.dart';
import '../models/prayer_collaborator_model.dart';
import '../models/group_model.dart';
import '../models/pending_group_member_model.dart';
import '../models/group_member_model.dart';
import '../models/group_prayer_model.dart';
import '../models/group_announcement_model.dart';
import '../models/group_feed_item.dart';
import '../repositories/folder_repository.dart';
import '../repositories/note_repository.dart';
import '../repositories/note_block_repository.dart';
import '../repositories/prayer_repository.dart';
import '../repositories/promise_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/song_repository.dart';
import '../repositories/prayer_log_repository.dart';
import '../repositories/prayer_update_repository.dart';
import '../models/prayer_update_model.dart';
import '../repositories/promise_condition_repository.dart';
import '../models/promise_condition_model.dart';
import '../repositories/promise_tag_repository.dart';
import '../repositories/prayer_tag_repository.dart';
import '../repositories/prayer_person_repository.dart';
import '../services/friends_api_service.dart';
import '../services/groups_api_service.dart';
import '../services/group_content_api_service.dart';
import '../services/shared_prayer_api_service.dart';
import '../../services/bible_api_service.dart';
import '../services/api_interceptor.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../services/group_join_service.dart';
import '../services/public_share_api_service.dart';
import '../services/user_search_service.dart';
import '../models/preacher_model.dart';
import '../models/tag_model.dart';
import '../repositories/preacher_repository.dart';
import '../repositories/tag_repository.dart';
import '../repositories/note_tag_repository.dart';
import '../repositories/song_tag_repository.dart';
import '../repositories/promise_prayer_link_repository.dart';
import '../repositories/entity_access_repository.dart';
import '../repositories/document_operations_repository.dart';
import '../models/entity_access_model.dart';
import '../repositories/feedback_thread_repository.dart';
import '../repositories/feedback_message_repository.dart';
import '../repositories/feedback_attachment_repository.dart';
import '../repositories/bible_reference_history_repository.dart';
import '../models/bible_reference_history_model.dart';
import '../models/feedback_thread_model.dart';
import '../models/feedback_message_model.dart';
import '../models/feedback_attachment_model.dart';
import '../../services/export_service.dart';
import '../../services/notification_service.dart';
import '../../services/pdf_export_service.dart';
import '../../services/prayer_reminder_service.dart';
import '../services/force_push_service.dart';
import '../services/trash_purge_service.dart';
import '../../../features/prayers/domain/services/prayer_analytics_service.dart';
import '../../../features/notes/domain/services/smart_collections_service.dart';

// ==================== DATABASE PROVIDER ====================

/// Provider for the sync-enabled database instance
/// Single instance shared across the app
final syncDatabaseProvider = Provider<SyncDatabase>((ref) {
  final database = SyncDatabase();
  ref.onDispose(() => database.close());
  return database;
});

// ==================== DEVICE ID PROVIDER ====================

/// Provider for the current device ID
/// This should be set during app initialization
final deviceIdProvider = StateProvider<String>((ref) {
  // Default device ID - should be replaced with actual device ID on init
  return 'default-device-id';
});

// ==================== USER ID PROVIDER ====================

/// Provider for the current user ID
/// This should be set after user authentication
final currentUserIdProvider = StateProvider<String>((ref) {
  // Default user ID - should be replaced with actual user ID after auth
  return 'default-user-id';
});

// ==================== REPOSITORY PROVIDERS ====================

/// Provider for the folder repository
final folderRepositoryProvider = Provider<FolderRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return FolderRepository(database, deviceId);
});

/// Provider for the note block FTS service
final noteBlockFtsServiceProvider = Provider<NoteBlockFtsService>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  return NoteBlockFtsService(database);
});

/// Provider for the note repository
final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final ftsService = ref.watch(noteBlockFtsServiceProvider);
  final entityAccessRepo = ref.watch(entityAccessRepositoryProvider);
  return NoteRepository(database, deviceId, ftsService, entityAccessRepo);
});

/// Provider for the note block repository
final noteBlockRepositoryProvider = Provider<NoteBlockRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final ftsService = ref.watch(noteBlockFtsServiceProvider);
  return NoteBlockRepository(database, deviceId, ftsService);
});

/// Provider for the prayer repository
final prayerRepositoryProvider = Provider<PrayerRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final entityAccessRepo = ref.watch(entityAccessRepositoryProvider);
  final repo = PrayerRepository(database, deviceId, entityAccessRepo);
  // Inject link repository for cascade deletes (lazy to avoid circular deps)
  repo.linkRepository = ref.watch(promisePrayerLinkRepositoryProvider);
  return repo;
});

/// Provider for the promise repository
final promiseRepositoryProvider = Provider<PromiseRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final entityAccessRepo = ref.watch(entityAccessRepositoryProvider);
  final repo = PromiseRepository(database, deviceId, entityAccessRepo);
  // Inject link repository for cascade deletes (lazy to avoid circular deps)
  repo.linkRepository = ref.watch(promisePrayerLinkRepositoryProvider);
  return repo;
});

/// Provider for the person repository
final personRepositoryProvider = Provider<PersonRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PersonRepository(database, deviceId);
});

// ==================== FOLDERS PROVIDERS ====================

/// Stream provider for note folders for current user
final noteFoldersStreamProvider = StreamProvider<List<FolderModel>>((ref) {
  final repository = ref.watch(folderRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllFolders(userId, type: 'note');
});

/// Stream provider for song folders for current user
final songFoldersStreamProvider = StreamProvider<List<FolderModel>>((ref) {
  final repository = ref.watch(folderRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllFolders(userId, type: 'song');
});

/// Backward-compatible alias (defaults to note folders)
final foldersStreamProvider = noteFoldersStreamProvider;

/// Future provider for soft-deleted note folders (for Trash/Restore)
final deletedNoteFoldersProvider = FutureProvider<List<FolderModel>>((ref) async {
  final repository = ref.watch(folderRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getDeletedFolders(userId, type: 'note');
});

/// Future provider to get root folders
final rootFoldersProvider = FutureProvider<List<FolderModel>>((ref) async {
  final repository = ref.watch(folderRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getRootFolders(userId);
});

/// Provider to get child folders of a specific folder
final childFoldersProvider = FutureProvider.family<List<FolderModel>, String>((ref, parentId) async {
  final repository = ref.watch(folderRepositoryProvider);
  return repository.getChildFolders(parentId);
});

/// Provider to get a single folder by ID
final folderByIdProvider = FutureProvider.family<FolderModel?, String>((ref, folderId) async {
  final repository = ref.watch(folderRepositoryProvider);
  return repository.getFolderById(folderId);
});

// ==================== NOTES PROVIDERS ====================

/// Stream provider for all notes for current user
final syncNotesStreamProvider = StreamProvider<List<NoteModel>>((ref) {
  final repository = ref.watch(noteRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllNotes(userId);
});

/// Provider to get notes in a specific folder
final notesInFolderProvider = StreamProvider.family<List<NoteModel>, String>((ref, folderId) {
  final repository = ref.watch(noteRepositoryProvider);
  return repository.watchNotesInFolder(folderId);
});

/// Provider to get a single note by ID
final noteByIdProvider = FutureProvider.family<NoteModel?, String>((ref, noteId) async {
  final repository = ref.watch(noteRepositoryProvider);
  return repository.getNoteById(noteId);
});

/// Provider for recent notes. The list length is backend-tunable (clamped).
/// Selects only the limit so an unrelated config change doesn't refetch.
final recentNotesProvider = FutureProvider<List<NoteModel>>((ref) async {
  final repository = ref.watch(noteRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  final limit = ref.watch(remoteConfigProvider
      .select((rc) => rc.getInt(RcKeys.recentNotesLimit, min: 1, max: 100)));
  return repository.getRecentNotes(userId, limit: limit);
});

// ==================== PRAYERS PROVIDERS ====================

/// Stream provider for all prayers
final prayersStreamProvider = StreamProvider<List<PrayerModel>>((ref) {
  final repository = ref.watch(prayerRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllPrayers(userId);
});

/// Stream provider for active prayers
final activePrayersStreamProvider = StreamProvider<List<PrayerModel>>((ref) {
  final repository = ref.watch(prayerRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchActivePrayers(userId);
});

/// Provider for prayers by status
final prayersByStatusProvider = StreamProvider.family<List<PrayerModel>, PrayerStatus>((ref, status) {
  final repository = ref.watch(prayerRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchPrayersByStatus(status, userId);
});

/// Provider to get a single prayer by ID
final prayerByIdProvider = FutureProvider.family<PrayerModel?, String>((ref, prayerId) async {
  final repository = ref.watch(prayerRepositoryProvider);
  return repository.getPrayerById(prayerId);
});

/// Provider for prayer counts by status
final prayerCountProvider = FutureProvider.family<int, PrayerStatus>((ref, status) async {
  final repository = ref.watch(prayerRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getPrayerCount(status, userId);
});

// ==================== PROMISES PROVIDERS ====================

/// Stream provider for all promises
final promisesStreamProvider = StreamProvider<List<PromiseModel>>((ref) {
  final repository = ref.watch(promiseRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllPromises(userId);
});

/// Stream provider for favorite promises
final favoritePromisesStreamProvider = StreamProvider<List<PromiseModel>>((ref) {
  final repository = ref.watch(promiseRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchFavoritePromises(userId);
});

/// Provider to get a single promise by ID
final promiseByIdProvider = FutureProvider.family<PromiseModel?, String>((ref, promiseId) async {
  final repository = ref.watch(promiseRepositoryProvider);
  return repository.getPromiseById(promiseId);
});

/// Provider for promise count
final promiseCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(promiseRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getPromiseCount(userId);
});

// ==================== PEOPLE PROVIDERS ====================

/// Stream provider for all people
final peopleStreamProvider = StreamProvider<List<PersonModel>>((ref) {
  final repository = ref.watch(personRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllPeople(userId);
});

/// Provider for people by relation/group
final peopleByRelationProvider = StreamProvider.family<List<PersonModel>, String>((ref, relation) {
  final repository = ref.watch(personRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchPeopleByRelation(relation, userId);
});

/// Provider to get a single person by ID
final personByIdProvider = FutureProvider.family<PersonModel?, String>((ref, personId) async {
  final repository = ref.watch(personRepositoryProvider);
  return repository.getPersonById(personId);
});

/// Provider for unique relations/groups
final uniqueRelationsProvider = FutureProvider<List<String>>((ref) async {
  final repository = ref.watch(personRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getUniqueRelations(userId);
});

/// Provider for person count
final personCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(personRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getPersonCount(userId);
});

// ==================== SONGS PROVIDERS ====================

/// Provider for the song repository
final songRepositoryProvider = Provider<SongRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  final entityAccessRepo = ref.watch(entityAccessRepositoryProvider);
  return SongRepository(database, deviceId, entityAccessRepo);
});

/// Stream provider for all songs
final songsStreamProvider = StreamProvider<List<SongModel>>((ref) {
  final repository = ref.watch(songRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllSongs(userId);
});

/// Stream provider for songs in a folder
final songsInFolderProvider = StreamProvider.family<List<SongModel>, String?>((ref, folderId) {
  final repository = ref.watch(songRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchSongsInFolder(folderId, userId);
});

/// Stream provider for favorite songs
final favoriteSongsStreamProvider = StreamProvider<List<SongModel>>((ref) {
  final repository = ref.watch(songRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchFavoriteSongs(userId);
});

/// Reactive stream provider for a single song by ID.
/// Automatically updates when the song row changes in the database.
final songByIdProvider = StreamProvider.family<SongModel?, String>((ref, songId) {
  final repository = ref.watch(songRepositoryProvider);
  return repository.watchSongById(songId);
});

/// Provider for song count
final songCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(songRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getSongCount(userId);
});

/// Provider for unique languages
final songLanguagesProvider = FutureProvider<List<String>>((ref) async {
  final repository = ref.watch(songRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getUniqueLanguages(userId);
});

/// Provider for unique scales/keys used across songs
final songScalesProvider = FutureProvider<List<String>>((ref) async {
  final repository = ref.watch(songRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getUniqueScales(userId);
});

/// Provider for unique tags used across songs.
/// Now returns global tags from the shared SyncTags table (same as notes).
final songTagsProvider = FutureProvider<List<TagModel>>((ref) async {
  final repository = ref.watch(tagRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.getAllTags(userId);
});

// ==================== SONG TAG PROVIDERS ====================

/// Provider for the song-tag repository
final songTagRepositoryProvider = Provider<SongTagRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return SongTagRepository(database, deviceId);
});

/// Stream provider for tag IDs associated with a song
final tagsForSongStreamProvider = StreamProvider.family<List<String>, String>((ref, songId) {
  final repository = ref.watch(songTagRepositoryProvider);
  return repository.watchTagIdsForSong(songId);
});

// ==================== PREACHER PROVIDERS ====================

/// Provider for the preacher repository
final preacherRepositoryProvider = Provider<PreacherRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PreacherRepository(database, deviceId);
});

/// Stream provider for all preachers for current user
final preachersStreamProvider = StreamProvider<List<PreacherModel>>((ref) {
  final repository = ref.watch(preacherRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllPreachers(userId);
});

/// Provider to get a preacher by ID
final preacherByIdProvider = FutureProvider.family<PreacherModel?, String>((ref, id) async {
  final repository = ref.watch(preacherRepositoryProvider);
  return repository.getPreacherById(id);
});

// ==================== TAG PROVIDERS ====================

/// Provider for the tag repository
final tagRepositoryProvider = Provider<TagRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return TagRepository(database, deviceId);
});

/// Stream provider for all tags for current user
final tagsStreamProvider = StreamProvider<List<TagModel>>((ref) {
  final repository = ref.watch(tagRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllTags(userId);
});

/// Provider to get a tag by ID
final tagByIdProvider = FutureProvider.family<TagModel?, String>((ref, id) async {
  final repository = ref.watch(tagRepositoryProvider);
  return repository.getTagById(id);
});

// ==================== NOTE TAG PROVIDERS ====================

/// Provider for the note-tag repository
final noteTagRepositoryProvider = Provider<NoteTagRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return NoteTagRepository(database, deviceId);
});

/// Provider for tag IDs associated with a note
final tagsForNoteProvider = FutureProvider.family<List<String>, String>((ref, noteId) async {
  final repository = ref.watch(noteTagRepositoryProvider);
  return repository.getTagIdsForNote(noteId);
});

/// Stream provider for tag IDs associated with a note
final tagsForNoteStreamProvider = StreamProvider.family<List<String>, String>((ref, noteId) {
  final repository = ref.watch(noteTagRepositoryProvider);
  return repository.watchTagIdsForNote(noteId);
});

// ==================== PRAYER LOG PROVIDERS ====================

/// Provider for the prayer log repository
final prayerLogRepositoryProvider = Provider<PrayerLogRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PrayerLogRepository(database, deviceId);
});

/// Stream provider for today's prayer logs
final todaysPrayerLogsProvider = StreamProvider<List<PrayerLogModel>>((ref) {
  final repository = ref.watch(prayerLogRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  final today = _todaySessionDate();
  return repository.watchLogsBySessionDate(today, userId);
});

/// Future provider for today's log count
final prayerLogCountTodayProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(prayerLogRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  final today = _todaySessionDate();
  return repository.getLogCountForDate(today, userId);
});

/// Future provider for prayer logs from the last 7 days (for dashboard history)
final weeklyPrayerLogsProvider = FutureProvider<List<PrayerLogModel>>((ref) async {
  final repository = ref.watch(prayerLogRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  final now = DateTime.now();
  final weekAgo = now.subtract(const Duration(days: 6));
  final startDate =
      '${weekAgo.year}-${weekAgo.month.toString().padLeft(2, '0')}-${weekAgo.day.toString().padLeft(2, '0')}';
  final endDate = _todaySessionDate();
  return repository.getLogsByDateRange(startDate, endDate, userId);
});

/// Stream provider for prayer logs by prayer ID
final prayerLogsByPrayerProvider =
    StreamProvider.family<List<PrayerLogModel>, String>((ref, prayerId) {
  final repository = ref.watch(prayerLogRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchLogsByPrayer(prayerId, userId);
});

// ==================== PRAYER UPDATE PROVIDERS ====================

/// Provider for the prayer update repository
final prayerUpdateRepositoryProvider = Provider<PrayerUpdateRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PrayerUpdateRepository(database, deviceId);
});

/// Stream provider for prayer updates by prayer ID
final prayerUpdatesByPrayerProvider =
    StreamProvider.family<List<PrayerUpdateModel>, String>((ref, prayerId) {
  final repository = ref.watch(prayerUpdateRepositoryProvider);
  return repository.watchUpdatesByPrayer(prayerId);
});

/// Stream provider for all prayer updates (global feed)
final allPrayerUpdatesProvider = StreamProvider<List<PrayerUpdateModel>>((ref) {
  final repository = ref.watch(prayerUpdateRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchAllUpdates(userId);
});

// ==================== PROMISE CONDITION PROVIDERS ====================

/// Provider for the promise condition repository
final promiseConditionRepositoryProvider =
    Provider<PromiseConditionRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PromiseConditionRepository(database, deviceId);
});

/// Stream provider for conditions by promise ID
final promiseConditionsByPromiseProvider =
    StreamProvider.family<List<PromiseConditionModel>, String>(
        (ref, promiseId) {
  final repository = ref.watch(promiseConditionRepositoryProvider);
  return repository.watchConditionsForPromise(promiseId);
});

// ==================== PROMISE TAG PROVIDERS ====================

/// Provider for the promise-tag repository
final promiseTagRepositoryProvider = Provider<PromiseTagRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PromiseTagRepository(database, deviceId);
});

/// Stream provider for tag IDs associated with a promise
final tagsForPromiseStreamProvider =
    StreamProvider.family<List<String>, String>((ref, promiseId) {
  final repository = ref.watch(promiseTagRepositoryProvider);
  return repository.watchTagIdsForPromise(promiseId);
});

// ==================== PRAYER TAG PROVIDERS ====================

/// Provider for the prayer-tag repository
final prayerTagRepositoryProvider = Provider<PrayerTagRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PrayerTagRepository(database, deviceId);
});

/// Stream provider for tag IDs associated with a prayer
final tagsForPrayerStreamProvider =
    StreamProvider.family<List<String>, String>((ref, prayerId) {
  final repository = ref.watch(prayerTagRepositoryProvider);
  return repository.watchTagIdsForPrayer(prayerId);
});

// ==================== PRAYER PERSON PROVIDERS ====================

/// Provider for the prayer-person repository
final prayerPersonRepositoryProvider = Provider<PrayerPersonRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PrayerPersonRepository(database, deviceId);
});

/// Stream provider for person IDs linked to a prayer
final peopleForPrayerStreamProvider =
    StreamProvider.family<List<String>, String>((ref, prayerId) {
  final repository = ref.watch(prayerPersonRepositoryProvider);
  return repository.watchPersonIdsForPrayer(prayerId);
});

/// Provider for unique people linked to any active prayer (for dashboard).
/// Uses a single JOIN query instead of N+1 sequential queries.
final prayerLinkedPeopleProvider = FutureProvider<List<PersonModel>>((ref) async {
  final prayerPersonRepo = ref.watch(prayerPersonRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return prayerPersonRepo.getPeopleLinkedToActivePrayers(userId, limit: 10);
});

// ==================== PROMISE-PRAYER LINK PROVIDERS ====================

/// Provider for the promise-prayer link repository
final promisePrayerLinkRepositoryProvider =
    Provider<PromisePrayerLinkRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return PromisePrayerLinkRepository(database, deviceId);
});

/// Stream provider for prayer IDs linked to a promise
final linkedPrayerIdsProvider =
    StreamProvider.family<List<String>, String>((ref, promiseId) {
  final repository = ref.watch(promisePrayerLinkRepositoryProvider);
  return repository.watchLinkedPrayerIds(promiseId);
});

/// Stream provider for promise IDs linked to a prayer
final linkedPromiseIdsProvider =
    StreamProvider.family<List<String>, String>((ref, prayerId) {
  final repository = ref.watch(promisePrayerLinkRepositoryProvider);
  return repository.watchLinkedPromiseIds(prayerId);
});

// ==================== ENTITY ACCESS (ACL) PROVIDERS ====================

/// Provider for the entity access repository
final entityAccessRepositoryProvider =
    Provider<EntityAccessRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return EntityAccessRepository(database, deviceId);
});

/// Stream provider for access records on a specific entity
final entityAccessStreamProvider =
    StreamProvider.family<List<EntityAccessModel>, ({String entityType, String entityId})>(
        (ref, params) {
  final repository = ref.watch(entityAccessRepositoryProvider);
  return repository.watchAccessForEntity(params.entityType, params.entityId);
});

/// Future provider for access records on a specific entity
final entityAccessProvider =
    FutureProvider.family<List<EntityAccessModel>, ({String entityType, String entityId})>(
        (ref, params) {
  final repository = ref.watch(entityAccessRepositoryProvider);
  return repository.getAccessForEntity(params.entityType, params.entityId);
});

/// Stream provider for all entities shared with a specific group
final groupSharedContentProvider =
    StreamProvider.family<List<EntityAccessModel>, String>((ref, groupId) {
  final repository = ref.watch(entityAccessRepositoryProvider);
  return repository.watchAccessForGroup(groupId);
});

/// Future provider for all access records owned by a user
final userAccessProvider =
    FutureProvider.family<List<EntityAccessModel>, ({String userId, String entityType})>(
        (ref, params) {
  final repository = ref.watch(entityAccessRepositoryProvider);
  return repository.getAccessByUserAndType(params.userId, params.entityType);
});

/// Live list of pending tier-2 user shares addressed to the current user —
/// what "Shared with me" renders in its inbox section.
final pendingIncomingSharesProvider =
    StreamProvider<List<EntityAccessModel>>((ref) {
  final repo = ref.watch(entityAccessRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId.isEmpty) return const Stream.empty();
  return repo.watchPendingSharesForTarget(userId);
});

/// Live list of accepted incoming shares — the active section of the inbox.
final acceptedIncomingSharesProvider =
    StreamProvider<List<EntityAccessModel>>((ref) {
  final repo = ref.watch(entityAccessRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId.isEmpty) return const Stream.empty();
  return repo.watchAcceptedSharesForTarget(userId);
});

// ==================== FEEDBACK PROVIDERS ====================

/// Provider for the feedback thread repository
final feedbackThreadRepositoryProvider =
    Provider<FeedbackThreadRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return FeedbackThreadRepository(database, deviceId);
});

/// Provider for the feedback message repository
final feedbackMessageRepositoryProvider =
    Provider<FeedbackMessageRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return FeedbackMessageRepository(database, deviceId);
});

/// Stream provider for all feedback threads for the current user
final feedbackThreadsStreamProvider =
    StreamProvider<List<FeedbackThreadModel>>((ref) {
  final repository = ref.watch(feedbackThreadRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchUserThreads(userId);
});

/// Stream provider for a single feedback thread by ID
final feedbackThreadByIdProvider =
    StreamProvider.family<FeedbackThreadModel?, String>((ref, threadId) {
  final repository = ref.watch(feedbackThreadRepositoryProvider);
  return repository.watchThreadById(threadId);
});

/// Stream provider for messages in a feedback thread
final feedbackMessagesStreamProvider =
    StreamProvider.family<List<FeedbackMessageModel>, String>(
        (ref, threadId) {
  final repository = ref.watch(feedbackMessageRepositoryProvider);
  return repository.watchThreadMessages(threadId);
});

/// Provider for the feedback attachment repository
final feedbackAttachmentRepositoryProvider =
    Provider<FeedbackAttachmentRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return FeedbackAttachmentRepository(database, deviceId);
});

/// Stream provider for attachments on a specific message
final feedbackAttachmentsStreamProvider =
    StreamProvider.family<List<FeedbackAttachmentModel>, String>(
        (ref, messageId) {
  final repository = ref.watch(feedbackAttachmentRepositoryProvider);
  return repository.watchMessageAttachments(messageId);
});

// ==================== DOCUMENT OPERATIONS (CRDT) PROVIDERS ====================

/// Provider for the document operations repository (local-only)
final documentOperationsRepositoryProvider =
    Provider<DocumentOperationsRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  return DocumentOperationsRepository(database);
});

/// Helper to get today's session date string (YYYY-MM-DD)
String _todaySessionDate() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

// ==================== BIBLE API SERVICE PROVIDERS ====================

/// Provider for the Bible API service
final bibleApiServiceProvider = Provider<BibleApiService>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final service = BibleApiService(database);
  ref.onDispose(() => service.dispose());
  return service;
});

// ==================== PROFILE COMPLETENESS PROVIDERS ====================

/// Whether the current user has completed their profile (username + displayName).
/// null = not yet determined, true = complete, false = incomplete/missing.
final profileCompleteProvider = StateProvider<bool?>((ref) => null);

/// Auto-updates profileCompleteProvider when the profile stream emits.
final profileCompletenessWatcherProvider = Provider<void>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  profileAsync.whenData((profile) {
    final isComplete = profile != null &&
        profile.username.trim().isNotEmpty &&
        profile.displayName.trim().isNotEmpty;
    final current = ref.read(profileCompleteProvider);
    if (current != isComplete) {
      Future.microtask(() {
        ref.read(profileCompleteProvider.notifier).state = isComplete;
      });
    }
  });
});

// ==================== DEEP LINK PROVIDERS ====================

/// Stores the intended deep link destination when the user is not authenticated.
/// After login + profile completion, the router reads this and navigates there.
final pendingDeepLinkProvider = StateProvider<String?>((ref) => null);

// ==================== SOCIAL API SERVICE PROVIDERS ====================

/// Provider for friends API service (profiles, friendships, friend requests, blocked users)
final friendsApiServiceProvider = Provider<FriendsApiService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  return FriendsApiService(config: config, authService: authService, interceptor: interceptor);
});

/// Provider for groups API service (groups, members, pending members)
final groupsApiServiceProvider = Provider<GroupsApiService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  return GroupsApiService(config: config, authService: authService, interceptor: interceptor);
});

/// Provider for group content API service (prayers, announcements)
final groupContentApiServiceProvider = Provider<GroupContentApiService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  return GroupContentApiService(config: config, authService: authService, interceptor: interceptor);
});

/// Provider for shared prayer API service (sharing, collaborators)
final sharedPrayerApiServiceProvider = Provider<SharedPrayerApiService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  return SharedPrayerApiService(config: config, authService: authService, interceptor: interceptor);
});

/// Provider for server-side user search
final userSearchServiceProvider = Provider<UserSearchService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  return UserSearchService(config: config, authService: authService, interceptor: interceptor);
});

/// Provider for server-side group lookup and join
final groupJoinServiceProvider = Provider<GroupJoinService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  return GroupJoinService(config: config, authService: authService, interceptor: interceptor);
});

/// Provider for public-link share tokens (create/list/revoke + resolve)
final publicShareApiServiceProvider = Provider<PublicShareApiService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  return PublicShareApiService(config: config, interceptor: interceptor);
});

// ==================== USER PROFILE PROVIDERS ====================

/// Future provider for current user's profile (fetched from server)
final currentUserProfileProvider = FutureProvider<UserProfileModel?>((ref) async {
  final api = ref.watch(friendsApiServiceProvider);
  return api.getCurrentProfile();
});

// ==================== USER STATS PROVIDERS ====================

/// Future provider for user stats (fetched from server)
final userStatsProvider = FutureProvider<UserStatsModel>((ref) async {
  final api = ref.watch(friendsApiServiceProvider);
  return api.getUserStats();
});

// ==================== FRIENDS PROVIDERS ====================

/// Future provider for friends list
final friendsListProvider = FutureProvider<List<FriendshipModel>>((ref) async {
  final api = ref.watch(friendsApiServiceProvider);
  return api.getFriends();
});

/// Future provider for incoming friend requests
final incomingFriendRequestsProvider = FutureProvider<List<FriendRequestModel>>((ref) async {
  final api = ref.watch(friendsApiServiceProvider);
  return api.getIncomingRequests();
});

/// Future provider for outgoing friend requests
final outgoingFriendRequestsProvider = FutureProvider<List<FriendRequestModel>>((ref) async {
  final api = ref.watch(friendsApiServiceProvider);
  return api.getOutgoingRequests();
});

/// Future provider for blocked users
final blockedUsersProvider = FutureProvider<List<BlockedUserModel>>((ref) async {
  final api = ref.watch(friendsApiServiceProvider);
  return api.getBlockedUsers();
});

/// Future provider for friend count
final friendCountProvider = FutureProvider<int>((ref) async {
  final api = ref.watch(friendsApiServiceProvider);
  return api.getFriendCount();
});

/// Future provider for pending request count
final pendingRequestCountProvider = FutureProvider<int>((ref) async {
  final api = ref.watch(friendsApiServiceProvider);
  return api.getPendingRequestCount();
});

// ==================== SHARED PRAYER PROVIDERS ====================

/// Future provider for shared prayer status by prayer ID
final sharedPrayerProvider =
    FutureProvider.family<SharedPrayerModel?, String>((ref, prayerId) async {
  final api = ref.watch(sharedPrayerApiServiceProvider);
  return api.getSharedPrayer(prayerId);
});

/// Future provider for prayer collaborators by prayer ID
final prayerCollaboratorsProvider =
    FutureProvider.family<List<PrayerCollaboratorModel>, String>((ref, prayerId) async {
  final api = ref.watch(sharedPrayerApiServiceProvider);
  return api.getCollaborators(prayerId);
});

// ==================== GROUP PROVIDERS ====================

/// Future provider for user's groups list
final groupsListProvider = FutureProvider<List<GroupModel>>((ref) async {
  final api = ref.watch(groupsApiServiceProvider);
  return api.getGroups();
});

/// Future provider for a single group by ID
final groupByIdProvider =
    FutureProvider.family<GroupModel?, String>((ref, groupId) async {
  final api = ref.watch(groupsApiServiceProvider);
  return api.getGroupById(groupId);
});

/// Future provider for group members by group ID
final groupMembersProvider =
    FutureProvider.family<List<GroupMemberModel>, String>((ref, groupId) async {
  final api = ref.watch(groupsApiServiceProvider);
  return api.getGroupMembers(groupId);
});

/// Future provider for group prayers by group ID
final groupPrayersProvider =
    FutureProvider.family<List<GroupPrayerModel>, String>((ref, groupId) async {
  final api = ref.watch(groupContentApiServiceProvider);
  return api.getGroupPrayers(groupId);
});

/// Future provider for group announcements by group ID
final groupAnnouncementsProvider =
    FutureProvider.family<List<GroupAnnouncementModel>, String>((ref, groupId) async {
  final api = ref.watch(groupContentApiServiceProvider);
  return api.getGroupAnnouncements(groupId);
});

/// Future provider for group activity feed by group ID.
/// Returns prayers + announcements merged and sorted by recency.
final groupFeedProvider =
    FutureProvider.family<List<GroupFeedItem>, String>((ref, groupId) async {
  final api = ref.watch(groupContentApiServiceProvider);
  return api.getGroupFeed(groupId);
});

/// Future provider for pending group members
final pendingGroupMembersProvider = FutureProvider.family<
    List<PendingGroupMemberModel>, String>((ref, groupId) async {
  final api = ref.watch(groupsApiServiceProvider);
  return api.getPendingMembers(groupId);
});

/// Future provider for group count
final groupCountProvider = FutureProvider<int>((ref) async {
  final api = ref.watch(groupsApiServiceProvider);
  return api.getGroupCount();
});

// ==================== SYNC SERVICE PROVIDERS ====================

/// Provider for sync configuration. The API/WS URLs come from the active
/// flavor; the numeric tuning knobs (timeouts, batch sizes, intervals, retries)
/// are overlaid from remote config so the backend can retune sync backpressure
/// without an app release. Every value is clamped to a safe band so a bad
/// server value can't thrash the client.
///
/// IMPORTANT: this watches ONLY the limit values via `.select` (a record with
/// structural equality), NOT the whole config snapshot. The sync service and
/// interceptor are torn down and rebuilt when this provider changes, so it must
/// rebuild only when a limit *actually* changes — never on an unrelated config
/// bump (a nav-tab rename must not restart sync), and not at all in the common
/// case where the server overrides no limits.
/// Override this in tests for different environments.
final syncConfigProvider = Provider<SyncConfig>((ref) {
  final limits = ref.watch(remoteConfigProvider.select((rc) => (
        httpTimeoutSec: rc.getInt(RcKeys.httpTimeoutSec, min: 3, max: 120),
        syncHttpTimeoutSec:
            rc.getInt(RcKeys.syncHttpTimeoutSec, min: 5, max: 180),
        maxBatchSize: rc.getInt(RcKeys.syncMaxBatchSize, min: 1, max: 1000),
        pullBatchSize: rc.getInt(RcKeys.syncPullBatchSize, min: 1, max: 1000),
        periodicSyncIntervalMin:
            rc.getInt(RcKeys.periodicSyncIntervalMin, min: 1, max: 1440),
        maxRetries: rc.getInt(RcKeys.syncMaxRetries, min: 0, max: 10),
      )));
  final wsUrl = AppConfig.apiBaseUrl
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');
  return SyncConfig(
    apiBaseUrl: AppConfig.apiBaseUrl,
    wsBaseUrl: wsUrl,
    httpTimeout: Duration(seconds: limits.httpTimeoutSec),
    syncHttpTimeout: Duration(seconds: limits.syncHttpTimeoutSec),
    maxBatchSize: limits.maxBatchSize,
    pullBatchSize: limits.pullBatchSize,
    periodicSyncInterval: Duration(minutes: limits.periodicSyncIntervalMin),
    maxRetries: limits.maxRetries,
  );
});

/// Provider for SharedPreferences instance
/// Must be overridden in ProviderScope during app initialization
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  );
});

/// Provider for auth service
/// Manages authentication tokens for sync API
final authServiceProvider = Provider<AuthService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final authService = AuthService(prefs);
  ref.onDispose(() => authService.dispose());
  return authService;
});

/// Provider for the shared API interceptor.
///
/// Provides automatic token refresh, retry with exponential backoff,
/// and request timeouts for all HTTP calls.
final apiInterceptorProvider = Provider<ApiInterceptor>((ref) {
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ApiInterceptor(
    config: config,
    authService: authService,
  );
  ref.onDispose(() => interceptor.dispose());
  return interceptor;
});

/// Provider for the sync service
/// This is the main entry point for sync functionality
final syncServiceProvider = FutureProvider<SyncService>((ref) async {
  final database = ref.watch(syncDatabaseProvider);
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ref.watch(apiInterceptorProvider);

  final ftsService = ref.watch(noteBlockFtsServiceProvider);

  final syncService = SyncService(
    db: database,
    config: config,
    authService: authService,
    interceptor: interceptor,
    ftsService: ftsService,
  );

  ref.onDispose(() => syncService.dispose());
  return syncService;
});

/// Provider for sync progress stream
final syncProgressProvider = StreamProvider<SyncProgress>((ref) async* {
  final syncService = await ref.watch(syncServiceProvider.future);
  yield* syncService.progressStream;
});

/// Provider for pending operations count
final pendingOpsCountProvider = FutureProvider<int>((ref) async {
  final syncService = await ref.watch(syncServiceProvider.future);
  return syncService.getPendingOpsCount();
});

/// Provider for sync initialization state
///
/// After initialization, updates [deviceIdProvider] with the real device ID
/// and [currentUserIdProvider] with the authenticated user's ID so that
/// repositories create oplog entries with correct attribution.
final syncInitializedProvider = FutureProvider<bool>((ref) async {
  final syncService = await ref.watch(syncServiceProvider.future);
  await syncService.initialize();

  // Bridge the real device ID back to the provider so all repositories
  // that depend on deviceIdProvider get the correct value.
  ref.read(deviceIdProvider.notifier).state = syncService.deviceId;

  // Bridge the authenticated user ID so repositories use the real value.
  final authService = ref.read(authServiceProvider);
  final userId = authService.currentUserId;
  if (userId != null) {
    ref.read(currentUserIdProvider.notifier).state = userId;
  }

  // Keep userId in sync when auth state changes
  final authSub = authService.authStateChanges.listen((token) {
    if (token != null) {
      ref.read(currentUserIdProvider.notifier).state = token.userId;
    }
  });
  ref.onDispose(authSub.cancel);

  return syncService.isInitialized;
});

/// One-time migration from AppDatabase → SyncDatabase for notes, preachers, tags.
/// Depends on syncInitializedProvider so that userId/deviceId are set.
final notesMigrationProvider = FutureProvider<void>((ref) async {
  // Wait for sync to be initialized (sets userId and deviceId)
  await ref.watch(syncInitializedProvider.future);

  final prefs = ref.read(sharedPreferencesProvider);
  final userId = ref.read(currentUserIdProvider);

  final migrationService = NotesMigrationService(
    oldDb: AppDatabase(),
    noteRepo: ref.read(noteRepositoryProvider),
    blockRepo: ref.read(noteBlockRepositoryProvider),
    preacherRepo: ref.read(preacherRepositoryProvider),
    tagRepo: ref.read(tagRepositoryProvider),
    noteTagRepo: ref.read(noteTagRepositoryProvider),
    prefs: prefs,
    userId: userId,
  );

  await migrationService.migrate();
});

/// One-time migration of inline promise tags (category column) and conditions
/// (JSON in notes column) into the promise_tags and promise_conditions tables.
/// Depends on syncInitializedProvider so that userId/deviceId are set.
final promiseInlineMigrationProvider = FutureProvider<void>((ref) async {
  await ref.watch(syncInitializedProvider.future);

  final prefs = ref.read(sharedPreferencesProvider);
  final userId = ref.read(currentUserIdProvider);

  final migrationService = PromiseInlineMigrationService(
    promiseRepo: ref.read(promiseRepositoryProvider),
    promiseTagRepo: ref.read(promiseTagRepositoryProvider),
    conditionRepo: ref.read(promiseConditionRepositoryProvider),
    tagRepo: ref.read(tagRepositoryProvider),
    prefs: prefs,
    userId: userId,
  );

  await migrationService.migrate();
});

/// Runs trash purge on app startup — permanently deletes items trashed > 30 days ago.
/// Depends on syncInitializedProvider so that userId/deviceId are set.
final trashPurgeOnStartupProvider = FutureProvider<void>((ref) async {
  await ref.watch(syncInitializedProvider.future);
  final purgeService = ref.read(trashPurgeServiceProvider);
  await purgeService.purgeExpiredItems();
});

/// Provider to check if user is authenticated for sync
final isSyncAuthenticatedProvider = Provider<bool>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.isAuthenticated;
});

// ==================== EXPORT SERVICE PROVIDERS ====================

/// Provider for JSON export service
final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(
    folderRepo: ref.watch(folderRepositoryProvider),
    noteRepo: ref.watch(noteRepositoryProvider),
    prayerRepo: ref.watch(prayerRepositoryProvider),
    promiseRepo: ref.watch(promiseRepositoryProvider),
    personRepo: ref.watch(personRepositoryProvider),
    songRepo: ref.watch(songRepositoryProvider),
    userId: ref.watch(currentUserIdProvider),
  );
});

/// Provider for PDF export service
final pdfExportServiceProvider = Provider<PdfExportService>((ref) {
  return PdfExportService(
    noteRepo: ref.watch(noteRepositoryProvider),
    noteBlockRepo: ref.watch(noteBlockRepositoryProvider),
    prayerRepo: ref.watch(prayerRepositoryProvider),
    userId: ref.watch(currentUserIdProvider),
  );
});

// ==================== FORCE PUSH PROVIDER ====================

/// Provider for the force push service
final forcePushServiceProvider = Provider<ForcePushService>((ref) {
  return ForcePushService(
    db: ref.watch(syncDatabaseProvider),
    deviceId: ref.watch(deviceIdProvider),
  );
});

// ==================== NOTIFICATION PROVIDERS ====================

/// Provider for the notification service singleton
/// Must be overridden in ProviderScope after initialization
final notificationServiceProvider = Provider<NotificationService>((ref) {
  throw UnimplementedError(
    'notificationServiceProvider must be overridden in ProviderScope',
  );
});

/// Provider for the prayer reminder service
final prayerReminderServiceProvider = Provider<PrayerReminderService>((ref) {
  return PrayerReminderService(
    notificationService: ref.watch(notificationServiceProvider),
    prayerRepo: ref.watch(prayerRepositoryProvider),
    userId: ref.watch(currentUserIdProvider),
  );
});

// ==================== PRAYER ANALYTICS PROVIDERS ====================

/// Provider for the prayer analytics service
final prayerAnalyticsServiceProvider = Provider<PrayerAnalyticsService>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  final userId = ref.watch(currentUserIdProvider);
  return PrayerAnalyticsService(db, userId);
});

/// Combined prayer counts (single query for total + answered)
final prayerCountsProvider =
    FutureProvider<({int total, int answered})>((ref) async {
  final service = ref.watch(prayerAnalyticsServiceProvider);
  return service.getPrayerCounts();
});

/// Total prayer count (derived from combined query)
final totalPrayerCountProvider = FutureProvider<int>((ref) async {
  final counts = await ref.watch(prayerCountsProvider.future);
  return counts.total;
});

/// Answered prayer count (derived from combined query)
final answeredPrayerCountProvider = FutureProvider<int>((ref) async {
  final counts = await ref.watch(prayerCountsProvider.future);
  return counts.answered;
});

/// Answered ratio (0.0–1.0, derived from combined query)
final answeredRatioProvider = FutureProvider<double>((ref) async {
  final counts = await ref.watch(prayerCountsProvider.future);
  if (counts.total == 0) return 0.0;
  return counts.answered / counts.total;
});

/// Prayer heatmap data (last 365 days)
final prayerHeatmapProvider = FutureProvider<Map<DateTime, int>>((ref) async {
  final service = ref.watch(prayerAnalyticsServiceProvider);
  return service.getPrayerHeatmap();
});

/// Current prayer streak (consecutive days)
final prayerStreakProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(prayerAnalyticsServiceProvider);
  return service.getStreak();
});

/// Frequently prayed prayers (top 10)
final frequentlyPrayedProvider =
    FutureProvider<List<({String prayerId, String title, int logCount})>>(
        (ref) async {
  final service = ref.watch(prayerAnalyticsServiceProvider);
  return service.getFrequentlyPrayed();
});

// ==================== SMART COLLECTIONS PROVIDERS ====================

/// Provider for the smart collections service
final smartCollectionsServiceProvider =
    Provider<SmartCollectionsService>((ref) {
  final db = ref.watch(syncDatabaseProvider);
  final userId = ref.watch(currentUserIdProvider);
  return SmartCollectionsService(db, userId);
});

/// Recently edited notes (top 20)
final recentlyEditedNotesProvider =
    FutureProvider<List<NoteModel>>((ref) async {
  final service = ref.watch(smartCollectionsServiceProvider);
  return service.getRecentlyEdited();
});

/// Untagged notes
final untaggedNotesProvider = FutureProvider<List<NoteModel>>((ref) async {
  final service = ref.watch(smartCollectionsServiceProvider);
  return service.getUntaggedNotes();
});

/// Stale notes (no activity in 30 days)
final staleNotesProvider = FutureProvider<List<NoteModel>>((ref) async {
  final service = ref.watch(smartCollectionsServiceProvider);
  return service.getStaleNotes();
});

// ==================== BIBLE REFERENCE HISTORY PROVIDERS ====================

/// Provider for the Bible reference history repository
final bibleReferenceHistoryRepositoryProvider =
    Provider<BibleReferenceHistoryRepository>((ref) {
  final database = ref.watch(syncDatabaseProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return BibleReferenceHistoryRepository(database, deviceId);
});

/// Watch recent Bible reference history (reactive stream)
final bibleReferenceHistoryStreamProvider =
    StreamProvider<List<BibleReferenceHistoryModel>>((ref) {
  final repository = ref.watch(bibleReferenceHistoryRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchRecentHistory(userId, limit: 200);
});

// ==================== TRASH PROVIDERS ====================

/// Watch trashed notes
final trashedNotesStreamProvider = StreamProvider<List<NoteModel>>((ref) {
  final repository = ref.watch(noteRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchTrashedNotes(userId);
});

/// Watch trashed folders
final trashedFoldersStreamProvider = StreamProvider<List<FolderModel>>((ref) {
  final repository = ref.watch(folderRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchTrashedFolders(userId);
});

/// Watch trashed prayers
final trashedPrayersStreamProvider = StreamProvider<List<PrayerModel>>((ref) {
  final repository = ref.watch(prayerRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchTrashedPrayers(userId);
});

/// Watch trashed promises
final trashedPromisesStreamProvider = StreamProvider<List<PromiseModel>>((ref) {
  final repository = ref.watch(promiseRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchTrashedPromises(userId);
});

/// Watch trashed people
final trashedPeopleStreamProvider = StreamProvider<List<PersonModel>>((ref) {
  final repository = ref.watch(personRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchTrashedPeople(userId);
});

/// Watch trashed songs
final trashedSongsStreamProvider = StreamProvider<List<SongModel>>((ref) {
  final repository = ref.watch(songRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchTrashedSongs(userId);
});

/// Watch trashed preachers
final trashedPreachersStreamProvider = StreamProvider<List<PreacherModel>>((ref) {
  final repository = ref.watch(preacherRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchTrashedPreachers(userId);
});

/// Watch trashed tags
final trashedTagsStreamProvider = StreamProvider<List<TagModel>>((ref) {
  final repository = ref.watch(tagRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  return repository.watchTrashedTags(userId);
});

/// Trash purge service — permanently deletes items trashed > 30 days ago
final trashPurgeServiceProvider = Provider<TrashPurgeService>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return TrashPurgeService(
    noteRepo: ref.watch(noteRepositoryProvider),
    folderRepo: ref.watch(folderRepositoryProvider),
    prayerRepo: ref.watch(prayerRepositoryProvider),
    promiseRepo: ref.watch(promiseRepositoryProvider),
    personRepo: ref.watch(personRepositoryProvider),
    songRepo: ref.watch(songRepositoryProvider),
    preacherRepo: ref.watch(preacherRepositoryProvider),
    tagRepo: ref.watch(tagRepositoryProvider),
    userId: userId,
  );
});
