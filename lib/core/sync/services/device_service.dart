import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../database/sync_database.dart';

/// Service for managing device identity
///
/// Per spec section 3.2:
/// Each device gets a unique ID that:
/// - Is included in every oplog entry
/// - Helps debug sync issues
/// - Enables conflict attribution
/// - Survives app reinstalls (persisted in DB)
class DeviceService {
  final SyncDatabase _db;

  String? _deviceId;
  String? _deviceName;

  DeviceService(this._db);

  /// Get current device ID
  ///
  /// Lazily initializes device on first call
  Future<String> getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    final device = await _db.getOrCreateCurrentDevice(
      deviceName: await _getDeviceName(),
      platform: _getPlatform(),
      appVersion: await _getAppVersion(),
    );

    _deviceId = device.id;
    _deviceName = device.name;
    return _deviceId!;
  }

  /// Get device name
  Future<String> getDeviceName() async {
    if (_deviceName != null) return _deviceName!;
    await getDeviceId(); // Initializes _deviceName
    return _deviceName!;
  }

  /// Get platform string
  String _getPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// Get device name from platform
  Future<String> _getDeviceName() async {
    // In production, use device_info_plus package
    // For now, return platform-based name
    final platform = _getPlatform();
    return '${platform.substring(0, 1).toUpperCase()}${platform.substring(1)} Device';
  }

  /// Get app version from the OS package metadata.
  Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }
}

/// Service locator for sync services
///
/// Provides centralized access to sync components
class SyncServiceLocator {
  static SyncServiceLocator? _instance;
  static SyncServiceLocator get instance => _instance ??= SyncServiceLocator._();

  SyncServiceLocator._();

  SyncDatabase? _database;
  DeviceService? _deviceService;

  /// Initialize the service locator
  Future<void> initialize(SyncDatabase database) async {
    _database = database;
    _deviceService = DeviceService(database);

    // Ensure device is registered
    await _deviceService!.getDeviceId();

    // Create indexes
    await database.createIndexes();
  }

  /// Get the sync database
  SyncDatabase get database {
    if (_database == null) {
      throw StateError('SyncServiceLocator not initialized');
    }
    return _database!;
  }

  /// Get the device service
  DeviceService get deviceService {
    if (_deviceService == null) {
      throw StateError('SyncServiceLocator not initialized');
    }
    return _deviceService!;
  }

  /// Get current device ID
  Future<String> getDeviceId() => deviceService.getDeviceId();

  /// Reset for testing
  void reset() {
    _database = null;
    _deviceService = null;
    _instance = null;
  }
}

/// UUID generator utility
class IdGenerator {
  static const _uuid = Uuid();

  /// Generate a new UUID v4
  static String generateId() => _uuid.v4();

  /// Generate a new operation ID
  static String generateOpId() => _uuid.v4();
}
