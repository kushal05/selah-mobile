// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'metadata_dao.dart';

// ignore_for_file: type=lint
mixin _$MetadataDaoMixin on DatabaseAccessor<AppDatabase> {
  $PreachersTable get preachers => attachedDatabase.preachers;
  $TagsTable get tags => attachedDatabase.tags;
  $NoteTagsTable get noteTags => attachedDatabase.noteTags;
  MetadataDaoManager get managers => MetadataDaoManager(this);
}

class MetadataDaoManager {
  final _$MetadataDaoMixin _db;
  MetadataDaoManager(this._db);
  $$PreachersTableTableManager get preachers =>
      $$PreachersTableTableManager(_db.attachedDatabase, _db.preachers);
  $$TagsTableTableManager get tags =>
      $$TagsTableTableManager(_db.attachedDatabase, _db.tags);
  $$NoteTagsTableTableManager get noteTags =>
      $$NoteTagsTableTableManager(_db.attachedDatabase, _db.noteTags);
}
