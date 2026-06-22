import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/sync/config/sync_config.dart';

/// Response model for a single version from GET /v1/bible/versions.
class BibleVersionDto {
  final String code;
  final String name;
  final String downloadUrl;
  final bool isDefault;
  final int approximateSizeMb;
  final int sortOrder;

  const BibleVersionDto({
    required this.code,
    required this.name,
    required this.downloadUrl,
    required this.isDefault,
    required this.approximateSizeMb,
    required this.sortOrder,
  });

  factory BibleVersionDto.fromJson(Map<String, dynamic> json) {
    return BibleVersionDto(
      code: json['code'] as String,
      name: json['name'] as String,
      downloadUrl: json['downloadUrl'] as String,
      isDefault: json['isDefault'] as bool? ?? false,
      approximateSizeMb: json['approximateSizeMb'] as int? ?? 8,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }
}

/// Fetches the list of available Bible translations from the public backend.
/// No authentication required.
class BibleVersionApiService {
  final SyncConfig config;
  final http.Client _client;

  BibleVersionApiService({required this.config, http.Client? client})
      : _client = client ?? http.Client();

  Future<List<BibleVersionDto>> getVersions() async {
    final uri = Uri.parse('${config.apiBaseUrl}/v1/bible/versions');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'BibleVersionApiService.getVersions failed: HTTP ${response.statusCode}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (body['versions'] as List? ?? []).cast<Map<String, dynamic>>();
    return list.map(BibleVersionDto.fromJson).toList();
  }
}
