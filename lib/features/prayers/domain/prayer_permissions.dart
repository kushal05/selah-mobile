import '../../../core/domain/enums/prayer_enums.dart';
import '../../../core/sync/models/prayer_collaborator_model.dart';
import '../../../core/sync/models/prayer_model.dart';
import '../../../core/sync/models/shared_prayer_model.dart';

/// What the signed-in user may do on a prayer screen.
class PrayerPermissions {
  final bool canEdit;
  final bool canLog;
  final bool canAddUpdates;
  final bool canManageSharing;

  const PrayerPermissions({
    required this.canEdit,
    required this.canLog,
    required this.canAddUpdates,
    required this.canManageSharing,
  });
}

/// The author can do everything. Anyone else can do nothing unless the prayer
/// is shared AND they are on it as a collaborator or viewer: having a share
/// row (or a share link) is not enough, so a stranger who merely holds the code
/// cannot log, edit or add updates.
PrayerPermissions computePrayerPermissions({
  required PrayerModel prayer,
  required String currentUserId,
  required SharedPrayerModel? sharedPrayer,
  required List<PrayerCollaboratorModel> collaborators,
}) {
  if (prayer.userId == currentUserId) {
    return const PrayerPermissions(
      canEdit: true,
      canLog: true,
      canAddUpdates: true,
      canManageSharing: true,
    );
  }

  if (sharedPrayer == null) {
    return const PrayerPermissions(
      canEdit: false,
      canLog: false,
      canAddUpdates: false,
      canManageSharing: false,
    );
  }

  PrayerCollaboratorModel? collaborator;
  for (final c in collaborators) {
    if (c.collaboratorUserId == currentUserId) {
      collaborator = c;
      break;
    }
  }
  final role = collaborator?.role;
  final canContribute =
      role == CollaboratorRole.owner || role == CollaboratorRole.collaborator;

  return PrayerPermissions(
    canEdit: sharedPrayer.allowEditing && canContribute,
    canLog: sharedPrayer.allowLogging && collaborator != null,
    canAddUpdates: sharedPrayer.allowUpdates && canContribute,
    canManageSharing: false,
  );
}
