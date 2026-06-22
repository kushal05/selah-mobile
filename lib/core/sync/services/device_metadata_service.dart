import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Captures device metadata for feedback threads
///
/// Uses device_info_plus to get real device model and OS version.
/// App version comes from the build config.
class DeviceMetadataService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Get device model string (e.g., "Pixel 7", "iPhone 15 Pro")
  static Future<String> getDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return '${info.manufacturer} ${info.model}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.utsname.machine;
      }
    } catch (_) {}
    return 'Unknown';
  }

  /// Get OS version string (e.g., "Android 14", "iOS 17.2")
  static Future<String> getOsVersion() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return 'Android ${info.version.release}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return 'iOS ${info.systemVersion}';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  /// Get app version from the OS package metadata.
  static Future<String> getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }
}
