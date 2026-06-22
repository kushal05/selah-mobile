import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/notes_table.dart';
import 'tables/preachers_table.dart';
import 'tables/tags_table.dart';
import 'daos/notes_dao.dart';
import 'daos/metadata_dao.dart';

part 'app_database.g.dart';

/// Main application database
/// Manages notes, preachers, tags, and their relationships
@DriftDatabase(
  tables: [Notes, Preachers, Tags, NoteTags],
  daos: [NotesDao, MetadataDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Migration from version 1 to 2: Add folder_id column to notes table
          if (from < 2) {
            await m.addColumn(notes, notes.folderId);
          }
        },
      );
}

/// Open connection to SQLite database
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'selah-prod.db'));
    return NativeDatabase(file);
  });
}
