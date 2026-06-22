import 'sync_entity.dart';
import '../../testing/test_clock.dart';

/// Feedback category types
enum FeedbackCategory {
  bug,
  featureRequest,
  uiIssue,
  performance,
  account,
  content,
  other;

  String toDbValue() {
    switch (this) {
      case FeedbackCategory.bug:
        return 'bug';
      case FeedbackCategory.featureRequest:
        return 'feature_request';
      case FeedbackCategory.uiIssue:
        return 'ui_issue';
      case FeedbackCategory.performance:
        return 'performance';
      case FeedbackCategory.account:
        return 'account';
      case FeedbackCategory.content:
        return 'content';
      case FeedbackCategory.other:
        return 'other';
    }
  }

  static FeedbackCategory fromDbValue(String value) {
    switch (value) {
      case 'bug':
        return FeedbackCategory.bug;
      case 'feature_request':
        return FeedbackCategory.featureRequest;
      case 'ui_issue':
        return FeedbackCategory.uiIssue;
      case 'performance':
        return FeedbackCategory.performance;
      case 'account':
        return FeedbackCategory.account;
      case 'content':
        return FeedbackCategory.content;
      case 'other':
        return FeedbackCategory.other;
      default:
        return FeedbackCategory.other;
    }
  }

  String get displayName {
    switch (this) {
      case FeedbackCategory.bug:
        return 'Bug';
      case FeedbackCategory.featureRequest:
        return 'Feature Request';
      case FeedbackCategory.uiIssue:
        return 'UI Issue';
      case FeedbackCategory.performance:
        return 'Performance';
      case FeedbackCategory.account:
        return 'Account';
      case FeedbackCategory.content:
        return 'Content';
      case FeedbackCategory.other:
        return 'Other';
    }
  }
}

/// Feedback thread status types
enum FeedbackStatus {
  open,
  inProgress,
  waitingForUser,
  resolved,
  closed;

  String toDbValue() {
    switch (this) {
      case FeedbackStatus.open:
        return 'open';
      case FeedbackStatus.inProgress:
        return 'in_progress';
      case FeedbackStatus.waitingForUser:
        return 'waiting_for_user';
      case FeedbackStatus.resolved:
        return 'resolved';
      case FeedbackStatus.closed:
        return 'closed';
    }
  }

  static FeedbackStatus fromDbValue(String value) {
    switch (value) {
      case 'open':
        return FeedbackStatus.open;
      case 'in_progress':
        return FeedbackStatus.inProgress;
      case 'waiting_for_user':
        return FeedbackStatus.waitingForUser;
      case 'resolved':
        return FeedbackStatus.resolved;
      case 'closed':
        return FeedbackStatus.closed;
      default:
        return FeedbackStatus.open;
    }
  }

  String get displayName {
    switch (this) {
      case FeedbackStatus.open:
        return 'Open';
      case FeedbackStatus.inProgress:
        return 'In Progress';
      case FeedbackStatus.waitingForUser:
        return 'Waiting for You';
      case FeedbackStatus.resolved:
        return 'Resolved';
      case FeedbackStatus.closed:
        return 'Closed';
    }
  }
}

/// Feedback thread priority types (set by admin)
enum FeedbackPriority {
  low,
  medium,
  high,
  critical;

  String toDbValue() {
    switch (this) {
      case FeedbackPriority.low:
        return 'low';
      case FeedbackPriority.medium:
        return 'medium';
      case FeedbackPriority.high:
        return 'high';
      case FeedbackPriority.critical:
        return 'critical';
    }
  }

  static FeedbackPriority fromDbValue(String value) {
    switch (value) {
      case 'low':
        return FeedbackPriority.low;
      case 'medium':
        return FeedbackPriority.medium;
      case 'high':
        return FeedbackPriority.high;
      case 'critical':
        return FeedbackPriority.critical;
      default:
        return FeedbackPriority.medium;
    }
  }

  String get displayName {
    switch (this) {
      case FeedbackPriority.low:
        return 'Low';
      case FeedbackPriority.medium:
        return 'Medium';
      case FeedbackPriority.high:
        return 'High';
      case FeedbackPriority.critical:
        return 'Critical';
    }
  }
}

/// Domain model for a feedback thread
class FeedbackThreadModel implements SyncEntity {
  @override
  final String id;

  final String userId;

  final String category;

  final String subject;

  final String status;

  final String priority;

  final int? lastMessageAt;

  final String? adminAssigned;

  final int unreadForUser;

  final int unreadForAdmin;

  final String? deviceModel;

  final String? osVersion;

  final String? appVersion;

  @override
  final int updatedAt;

  @override
  final int version;

  final int deleted;

  @override
  final int? trashedAt;

  final int createdAt;

  final Map<String, dynamic> fieldUpdatedAt;

  const FeedbackThreadModel({
    required this.id,
    required this.userId,
    required this.category,
    required this.subject,
    required this.status,
    this.priority = 'medium',
    this.lastMessageAt,
    this.adminAssigned,
    this.unreadForUser = 0,
    this.unreadForAdmin = 0,
    this.deviceModel,
    this.osVersion,
    this.appVersion,
    required this.updatedAt,
    required this.version,
    required this.deleted,
    this.trashedAt,
    required this.createdAt,
    this.fieldUpdatedAt = const {},
  });

  @override
  bool get isDeleted => deleted == 1;

  FeedbackCategory get categoryEnum => FeedbackCategory.fromDbValue(category);

  FeedbackStatus get statusEnum => FeedbackStatus.fromDbValue(status);

  FeedbackPriority get priorityEnum => FeedbackPriority.fromDbValue(priority);

  bool get isClosed => statusEnum == FeedbackStatus.closed;

  bool get hasUnread => unreadForUser > 0;

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'category': category,
      'subject': subject,
      'status': status,
      'priority': priority,
      'lastMessageAt': lastMessageAt,
      'adminAssigned': adminAssigned,
      'unreadForUser': unreadForUser,
      'unreadForAdmin': unreadForAdmin,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
      'appVersion': appVersion,
      'updatedAt': updatedAt,
      'version': version,
      'deleted': deleted,
      if (trashedAt != null) 'trashedAt': trashedAt,
      'createdAt': createdAt,
      'fieldUpdatedAt': fieldUpdatedAt,
    };
  }

  factory FeedbackThreadModel.fromJson(Map<String, dynamic> json) {
    return FeedbackThreadModel(
      id: (json['id'] ?? json['_id']) as String,
      userId: json['userId'] as String,
      category: json['category'] as String,
      subject: json['subject'] as String,
      status: json['status'] as String? ?? 'open',
      priority: json['priority'] as String? ?? 'medium',
      lastMessageAt: json['lastMessageAt'] as int?,
      adminAssigned: json['adminAssigned'] as String?,
      unreadForUser: json['unreadForUser'] as int? ?? 0,
      unreadForAdmin: json['unreadForAdmin'] as int? ?? 0,
      deviceModel: json['deviceModel'] as String?,
      osVersion: json['osVersion'] as String?,
      appVersion: json['appVersion'] as String?,
      updatedAt: json['updatedAt'] as int,
      version: json['version'] as int,
      deleted: _parseDeleted(json['deleted']),
      trashedAt: json['trashedAt'] as int?,
      createdAt: json['createdAt'] as int,
      fieldUpdatedAt: json['fieldUpdatedAt'] is Map
          ? Map<String, dynamic>.from(json['fieldUpdatedAt'] as Map)
          : const {},
    );
  }

  factory FeedbackThreadModel.create({
    required String id,
    required String userId,
    required String category,
    required String subject,
    String? deviceModel,
    String? osVersion,
    String? appVersion,
  }) {
    final now = TestClock.now();
    return FeedbackThreadModel(
      id: id,
      userId: userId,
      category: category,
      subject: subject,
      status: 'open',
      priority: 'medium',
      lastMessageAt: now,
      unreadForAdmin: 1,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: appVersion,
      updatedAt: now,
      version: 1,
      deleted: 0,
      createdAt: now,
    );
  }

  FeedbackThreadModel copyWithUpdate({
    String? status,
    String? priority,
    int? lastMessageAt,
    String? adminAssigned,
    int? unreadForUser,
    int? unreadForAdmin,
  }) {
    return FeedbackThreadModel(
      id: id,
      userId: userId,
      category: category,
      subject: subject,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      adminAssigned: adminAssigned ?? this.adminAssigned,
      unreadForUser: unreadForUser ?? this.unreadForUser,
      unreadForAdmin: unreadForAdmin ?? this.unreadForAdmin,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: appVersion,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: deleted,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  FeedbackThreadModel softDelete() {
    return FeedbackThreadModel(
      id: id,
      userId: userId,
      category: category,
      subject: subject,
      status: status,
      priority: priority,
      lastMessageAt: lastMessageAt,
      adminAssigned: adminAssigned,
      unreadForUser: unreadForUser,
      unreadForAdmin: unreadForAdmin,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: appVersion,
      updatedAt: TestClock.now(),
      version: version + 1,
      deleted: 1,
      trashedAt: trashedAt,
      createdAt: createdAt,
      fieldUpdatedAt: fieldUpdatedAt,
    );
  }

  static int _parseDeleted(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is int) return value;
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackThreadModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'FeedbackThreadModel(id: $id, subject: $subject, status: $status, v$version)';
  }
}
