import 'package:drift/drift.dart';

/// Pending group membership requests (for groups with 'approval' join policy).
///
/// Created when a user requests to join a group. Admin approves or rejects.
/// - Approved: a GroupMember record is created, this record is soft-deleted.
/// - Rejected: this record is soft-deleted.
class PendingGroupMembers extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get requestingUserId => text()();
  TextColumn get requestingUsername => text().withDefault(const Constant(''))();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending, approved, rejected
  TextColumn get userId => text()(); // owner user ID (for sync scoping)
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get deleted => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
