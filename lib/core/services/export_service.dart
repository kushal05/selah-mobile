import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../sync/repositories/folder_repository.dart';
import '../sync/repositories/note_repository.dart';
import '../sync/repositories/prayer_repository.dart';
import '../sync/repositories/promise_repository.dart';
import '../sync/repositories/person_repository.dart';
import '../sync/repositories/song_repository.dart';

/// Service for exporting all user data as JSON
class ExportService {
  final FolderRepository _folderRepo;
  final NoteRepository _noteRepo;
  final PrayerRepository _prayerRepo;
  final PromiseRepository _promiseRepo;
  final PersonRepository _personRepo;
  final SongRepository _songRepo;
  final String _userId;

  ExportService({
    required FolderRepository folderRepo,
    required NoteRepository noteRepo,
    required PrayerRepository prayerRepo,
    required PromiseRepository promiseRepo,
    required PersonRepository personRepo,
    required SongRepository songRepo,
    required String userId,
  })  : _folderRepo = folderRepo,
        _noteRepo = noteRepo,
        _prayerRepo = prayerRepo,
        _promiseRepo = promiseRepo,
        _personRepo = personRepo,
        _songRepo = songRepo,
        _userId = userId;

  /// Export all data as a JSON file and share it
  Future<void> exportAllDataAsJson() async {
    try {
      final results = await Future.wait([
        _folderRepo.getAllFolders(_userId),
        _noteRepo.getAllNotes(_userId),
        _prayerRepo.getAllPrayers(_userId),
        _promiseRepo.getAllPromises(_userId),
        _personRepo.getAllPeople(_userId),
        _songRepo.getAllSongs(_userId),
      ]);

      final data = {
        'exportedAt': DateTime.now().toIso8601String(),
        'version': '1.0.0',
        'folders': results[0].map((e) => e.toJson()).toList(),
        'notes': results[1].map((e) => e.toJson()).toList(),
        'prayers': results[2].map((e) => e.toJson()).toList(),
        'promises': results[3].map((e) => e.toJson()).toList(),
        'people': results[4].map((e) => e.toJson()).toList(),
        'songs': results[5].map((e) => e.toJson()).toList(),
      };

      // Encode JSON off the main isolate — can be large with many notes/prayers.
      final jsonString = await compute(
        (Map<String, dynamic> d) => const JsonEncoder.withIndent('  ').convert(d),
        data,
      );

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/notify_export_$timestamp.json');
      await file.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Selah Data Export',
      );
    } catch (e, stackTrace) {
      debugPrint('ExportService.exportAllDataAsJson failed: $e\n$stackTrace');
      rethrow;
    }
  }
}
