import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/sync/config/sync_config.dart';
import '../../domain/models/changelog_entry.dart';

/// Fetches changelog entries from the public backend endpoint.
/// No auth required — uses a plain HTTP GET.
class ChangelogApiService {
  final SyncConfig config;
  final http.Client _client;

  ChangelogApiService({required this.config, http.Client? client})
      : _client = client ?? http.Client();

  Future<List<ChangelogEntry>> getEntries() async {
    final uri = Uri.parse('${config.apiBaseUrl}/v1/app/changelog');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
          'ChangelogApiService.getEntries failed: HTTP ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list =
        (body['entries'] as List? ?? []).cast<Map<String, dynamic>>();
    return list.map(ChangelogEntry.fromJson).toList();
  }
}
