// Who may do what on someone else's shared prayer. The bug this pins: holding a
// share row (or the share link) used to be enough to log a prayer; the person
// also has to be on the prayer.

import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/domain/enums/prayer_enums.dart';
import 'package:notify/core/sync/models/prayer_collaborator_model.dart';
import 'package:notify/core/sync/models/prayer_model.dart';
import 'package:notify/core/sync/models/shared_prayer_model.dart';
import 'package:notify/features/prayers/domain/prayer_permissions.dart';

PrayerModel _prayer() => PrayerModel(
      id: 'p1',
      userId: 'author',
      title: 'T',
      content: 'C',
      frequency: PrayerFrequency.daily,
      status: PrayerStatus.active,
      category: 'personal',
      answeredAt: null,
      updatedAt: 1,
      version: 1,
      deleted: 0,
      createdAt: 1,
    );

SharedPrayerModel _share({
  bool editing = false,
  bool logging = true,
  bool updates = true,
}) =>
    SharedPrayerModel(
      id: 's1',
      prayerId: 'p1',
      sharedByUserId: 'author',
      shareCode: 'ABCDEF123456',
      allowEditing: editing,
      allowLogging: logging,
      allowUpdates: updates,
      userId: 'author',
      updatedAt: 1,
      version: 1,
      deleted: 0,
      createdAt: 1,
    );

PrayerCollaboratorModel _collab(String userId, CollaboratorRole role) =>
    PrayerCollaboratorModel(
      id: 'c-$userId',
      prayerId: 'p1',
      sharedPrayerId: 's1',
      collaboratorUserId: userId,
      collaboratorUsername: userId,
      role: role,
      addedByUserId: 'author',
      userId: 'author',
      updatedAt: 1,
      version: 1,
      deleted: 0,
      createdAt: 1,
    );

PrayerPermissions _for(
  String me, {
  SharedPrayerModel? share,
  List<PrayerCollaboratorModel> collabs = const [],
}) =>
    computePrayerPermissions(
      prayer: _prayer(),
      currentUserId: me,
      sharedPrayer: share,
      collaborators: collabs,
    );

void _expectNone(PrayerPermissions p) {
  expect(p.canEdit, isFalse);
  expect(p.canLog, isFalse);
  expect(p.canAddUpdates, isFalse);
  expect(p.canManageSharing, isFalse);
}

void main() {
  test('the author can do everything', () {
    final p = _for('author');
    expect([p.canEdit, p.canLog, p.canAddUpdates, p.canManageSharing],
        everyElement(isTrue));
  });

  test('someone with no share row can do nothing', () {
    _expectNone(_for('stranger'));
  });

  test('a stranger who has only the share row cannot log (the bug)', () {
    final p = _for('stranger', share: _share(editing: true));
    _expectNone(p);
  });

  test('a viewer on the prayer can log, but not edit or add updates', () {
    final p = _for('viewer',
        share: _share(editing: true),
        collabs: [_collab('viewer', CollaboratorRole.viewer)]);
    expect(p.canLog, isTrue);
    expect(p.canEdit, isFalse);
    expect(p.canAddUpdates, isFalse);
    expect(p.canManageSharing, isFalse);
  });

  test('a collaborator can edit and add updates when the share allows it', () {
    final p = _for('helper',
        share: _share(editing: true),
        collabs: [_collab('helper', CollaboratorRole.collaborator)]);
    expect(p.canEdit, isTrue);
    expect(p.canAddUpdates, isTrue);
    expect(p.canLog, isTrue);
    expect(p.canManageSharing, isFalse, reason: 'only the author manages sharing');
  });

  test('the share switches still apply to collaborators', () {
    final p = _for('helper',
        share: _share(logging: false, updates: false),
        collabs: [_collab('helper', CollaboratorRole.collaborator)]);
    expect(p.canLog, isFalse);
    expect(p.canAddUpdates, isFalse);
    expect(p.canEdit, isFalse);
  });

  test("another person's collaborator row does not grant me anything", () {
    final p = _for('stranger',
        share: _share(editing: true),
        collabs: [_collab('someone-else', CollaboratorRole.collaborator)]);
    _expectNone(p);
  });
}
