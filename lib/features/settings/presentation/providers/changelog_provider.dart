import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/sync/providers/sync_providers.dart';
import '../../data/services/changelog_api_service.dart';
import '../../domain/models/changelog_entry.dart';

final changelogApiServiceProvider = Provider<ChangelogApiService>((ref) {
  final config = ref.watch(syncConfigProvider);
  final client = http.Client();
  ref.onDispose(client.close);
  return ChangelogApiService(config: config, client: client);
});

final changelogProvider = FutureProvider<List<ChangelogEntry>>((ref) async {
  final service = ref.watch(changelogApiServiceProvider);
  return service.getEntries();
});
