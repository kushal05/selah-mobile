/// Friend request status
enum FriendRequestStatus {
  pending,
  accepted,
  rejected;

  String get displayName {
    switch (this) {
      case FriendRequestStatus.pending:
        return 'Pending';
      case FriendRequestStatus.accepted:
        return 'Accepted';
      case FriendRequestStatus.rejected:
        return 'Rejected';
    }
  }
}
