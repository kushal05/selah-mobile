/// Prayer frequency options
enum PrayerFrequency {
  daily,
  weekdays,
  weekly,
  monthly,
  asNeeded;

  String get displayName {
    switch (this) {
      case PrayerFrequency.daily:
        return 'Daily';
      case PrayerFrequency.weekdays:
        return 'Weekdays';
      case PrayerFrequency.weekly:
        return 'Weekly';
      case PrayerFrequency.monthly:
        return 'Monthly';
      case PrayerFrequency.asNeeded:
        return 'As Needed';
    }
  }
}

/// Prayer status options
enum PrayerStatus {
  active,
  answered,
  archived;

  String get displayName {
    switch (this) {
      case PrayerStatus.active:
        return 'Active';
      case PrayerStatus.answered:
        return 'Answered';
      case PrayerStatus.archived:
        return 'Archived';
    }
  }
}

/// Collaborator role in a shared prayer
enum CollaboratorRole {
  owner,
  collaborator,
  viewer;

  String get displayName {
    switch (this) {
      case CollaboratorRole.owner:
        return 'Owner';
      case CollaboratorRole.collaborator:
        return 'Collaborator';
      case CollaboratorRole.viewer:
        return 'Viewer';
    }
  }
}
