import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../features/promises/domain/models/promise_conditions_codec.dart';
import '../../sync/models/promise_condition_model.dart';
import '../../sync/repositories/promise_condition_repository.dart';
import '../../sync/repositories/promise_repository.dart';
import '../../sync/repositories/promise_tag_repository.dart';
import '../../sync/repositories/tag_repository.dart';

const _kMigrationFlag = 'promise_inline_migrated';

/// One-time migration that moves inline promise tags (from `category` column)
/// and inline conditions (JSON-encoded in `notes` column) into the proper
/// junction tables (`promise_tags`, `promise_conditions`) so they produce
/// oplog entries and sync to the server.
class PromiseInlineMigrationService {
  final PromiseRepository _promiseRepo;
  final PromiseTagRepository _promiseTagRepo;
  final PromiseConditionRepository _conditionRepo;
  final TagRepository _tagRepo;
  final SharedPreferences _prefs;
  final String _userId;

  PromiseInlineMigrationService({
    required PromiseRepository promiseRepo,
    required PromiseTagRepository promiseTagRepo,
    required PromiseConditionRepository conditionRepo,
    required TagRepository tagRepo,
    required SharedPreferences prefs,
    required String userId,
  })  : _promiseRepo = promiseRepo,
        _promiseTagRepo = promiseTagRepo,
        _conditionRepo = conditionRepo,
        _tagRepo = tagRepo,
        _prefs = prefs,
        _userId = userId;

  /// Returns true if migration has already been completed.
  bool get isMigrated => _prefs.getBool(_kMigrationFlag) ?? false;

  /// Run the migration. Safe to call multiple times — will no-op if already done.
  Future<void> migrate() async {
    if (isMigrated) return;

    developer.log(
        'PromiseInlineMigration: Starting migration of inline tags & conditions');

    try {
      final allPromises = await _promiseRepo.getAllPromises(_userId);
      developer
          .log('PromiseInlineMigration: Processing ${allPromises.length} promises');

      for (final promise in allPromises) {
        try {
          await _migrateTagsForPromise(promise.id, promise.category);
          await _migrateConditionsForPromise(
              promise.id, promise.notes);
        } catch (e, stack) {
          developer.log(
            'PromiseInlineMigration: Failed to migrate promise ${promise.id}, skipping',
            error: e,
            stackTrace: stack,
          );
          continue;
        }
      }

      await _prefs.setBool(_kMigrationFlag, true);
      developer.log('PromiseInlineMigration: Migration complete');
    } catch (e, stack) {
      developer.log(
        'PromiseInlineMigration: Migration failed',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Migrate comma-separated tags from `category` field into `promise_tags`.
  Future<void> _migrateTagsForPromise(
      String promiseId, String? category) async {
    if (category == null || category.trim().isEmpty) return;

    final tagNames = category
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (tagNames.isEmpty) return;

    // Check if tags already exist for this promise (avoid double-migration)
    final existingTagIds =
        await _promiseTagRepo.getTagIdsForPromise(promiseId);
    if (existingTagIds.isNotEmpty) return;

    for (final tagName in tagNames) {
      final tag = await _tagRepo.getOrCreateTag(tagName, _userId);
      await _promiseTagRepo.addTagToPromise(
        promiseId: promiseId,
        tagId: tag.id,
        userId: _userId,
      );
    }

    developer.log(
        'PromiseInlineMigration: Migrated ${tagNames.length} tags for promise $promiseId');
  }

  /// Migrate JSON-encoded conditions from `notes` field into `promise_conditions`.
  /// Also strips the conditions section from the notes, leaving only user notes.
  Future<void> _migrateConditionsForPromise(
      String promiseId, String notes) async {
    if (!notes.contains(promiseConditionsSeparator)) return;

    // Check if conditions already exist for this promise (avoid double-migration)
    final existingConditions =
        await _conditionRepo.getConditionsForPromise(promiseId);
    if (existingConditions.isNotEmpty) return;

    final parsed = parsePromiseNotesWithConditions(notes);
    if (parsed.conditions.isEmpty) return;

    for (final item in parsed.conditions) {
      // Map legacy 'ONGOING' status → 'ACTIVE'
      final status = _mapStatus(item.status);

      await _conditionRepo.addCondition(
        promiseId: promiseId,
        userId: _userId,
        description: item.description,
        notes: item.notes ?? '',
        status: status,
      );
    }

    // Update the promise notes to contain only the user notes (strip conditions JSON)
    await _promiseRepo.updatePromise(
      id: promiseId,
      notes: parsed.userNotes,
    );

    developer.log(
        'PromiseInlineMigration: Migrated ${parsed.conditions.length} conditions for promise $promiseId');
  }

  /// Maps legacy status strings to [PromiseConditionStatus].
  PromiseConditionStatus _mapStatus(String status) {
    switch (status.toUpperCase()) {
      case 'MET':
        return PromiseConditionStatus.met;
      case 'NOT_MET':
        return PromiseConditionStatus.notMet;
      case 'ONGOING':
        // Legacy value — treat as active
        return PromiseConditionStatus.active;
      case 'ACTIVE':
      default:
        return PromiseConditionStatus.active;
    }
  }
}
