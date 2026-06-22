import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../data/services/device_api_service.dart';
import '../../domain/models/device.dart';

/// Provider for the device API service
final deviceApiServiceProvider = Provider<DeviceApiService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final authService = ref.watch(authServiceProvider);
  final interceptor = ref.watch(apiInterceptorProvider);
  final deviceId = ref.watch(deviceIdProvider);
  return DeviceApiService(
    config: config,
    authService: authService,
    interceptor: interceptor,
    deviceId: deviceId,
  );
});

/// Provider that fetches the list of devices and maps to domain models
final devicesListProvider = FutureProvider<List<Device>>((ref) async {
  final api = ref.watch(deviceApiServiceProvider);
  final models = await api.getDevices();
  return models
      .map((m) => Device(
            id: m.id,
            name: m.name,
            platform: m.platform,
            lastActiveAt: m.lastActiveAt,
          ))
      .toList();
});
