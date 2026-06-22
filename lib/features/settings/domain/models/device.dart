import 'package:flutter/foundation.dart';

/// Pure domain model for a user device.
///
/// Contains only the fields needed by the presentation layer.
/// No sync metadata (version, deleted, fieldUpdatedAt).
@immutable
class Device {
  /// Unique device identifier.
  final String id;

  /// Human-readable device name.
  final String name;

  /// Platform string (e.g., 'android', 'ios', 'windows').
  final String platform;

  /// Last time the device was active.
  final DateTime lastActiveAt;

  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastActiveAt,
  });
}
