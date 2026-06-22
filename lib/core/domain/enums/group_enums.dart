/// Group type enum
enum GroupType {
  church,
  smallGroup,
  prayerGroup,
  ministry,
  other;

  String get displayName {
    switch (this) {
      case GroupType.church:
        return 'Church';
      case GroupType.smallGroup:
        return 'Small Group';
      case GroupType.prayerGroup:
        return 'Prayer Group';
      case GroupType.ministry:
        return 'Ministry';
      case GroupType.other:
        return 'Other';
    }
  }
}

/// Join policy for a group
enum GroupJoinPolicy {
  codeOnly,
  open,
  approval;

  String get displayName {
    switch (this) {
      case GroupJoinPolicy.codeOnly:
        return 'Invite Only';
      case GroupJoinPolicy.open:
        return 'Open';
      case GroupJoinPolicy.approval:
        return 'Requires Approval';
    }
  }

  String get description {
    switch (this) {
      case GroupJoinPolicy.codeOnly:
        return 'Members join by invite code';
      case GroupJoinPolicy.open:
        return 'Anyone can search and join';
      case GroupJoinPolicy.approval:
        return 'Members request to join, admin approves';
    }
  }
}

/// Member role in a group
enum GroupMemberRole {
  admin,
  moderator,
  member;

  String get displayName {
    switch (this) {
      case GroupMemberRole.admin:
        return 'Admin';
      case GroupMemberRole.moderator:
        return 'Moderator';
      case GroupMemberRole.member:
        return 'Member';
    }
  }
}
