import '../models/prayer_collaborator_model.dart';
import '../models/shared_prayer_model.dart';
import 'base_social_api_service.dart';

/// Online-required API service for shared prayers and collaborators.
class SharedPrayerApiService extends BaseSocialApiService {
  SharedPrayerApiService({
    required super.config,
    required super.authService,
    required super.interceptor,
  });

  // ==================== SHARED PRAYERS ====================

  /// Get the shared status of a prayer.
  Future<SharedPrayerModel?> getSharedPrayer(String prayerId) async {
    final response = await httpGet('/prayers/$prayerId/sharing');
    if (response.statusCode == 404) return null;
    assertSuccess(response, 'Get shared prayer');
    final body = parseBody(response);
    final shared = body['sharedPrayer'] as Map<String, dynamic>?;
    if (shared == null) return null;
    return SharedPrayerModel.fromJson(shared);
  }

  /// Share a prayer. Server generates share code.
  Future<SharedPrayerModel> sharePrayer({
    required String prayerId,
    bool allowEditing = false,
    bool allowLogging = true,
    bool allowUpdates = true,
  }) async {
    final response = await httpPost('/prayers/$prayerId/share', body: {
      'allowEditing': allowEditing,
      'allowLogging': allowLogging,
      'allowUpdates': allowUpdates,
    });
    assertSuccess(response, 'Share prayer');
    final body = parseBody(response);
    return SharedPrayerModel.fromJson(
        body['sharedPrayer'] as Map<String, dynamic>);
  }

  /// Stop sharing a prayer.
  Future<void> unsharePrayer(String prayerId) async {
    final response = await httpDelete('/prayers/$prayerId/share');
    assertSuccess(response, 'Unshare prayer');
  }

  /// Update sharing permissions.
  Future<SharedPrayerModel> updatePermissions({
    required String prayerId,
    bool? allowEditing,
    bool? allowLogging,
    bool? allowUpdates,
  }) async {
    final body = <String, dynamic>{};
    if (allowEditing != null) body['allowEditing'] = allowEditing;
    if (allowLogging != null) body['allowLogging'] = allowLogging;
    if (allowUpdates != null) body['allowUpdates'] = allowUpdates;

    final response =
        await httpPut('/prayers/$prayerId/share/permissions', body: body);
    assertSuccess(response, 'Update permissions');
    final data = parseBody(response);
    return SharedPrayerModel.fromJson(
        data['sharedPrayer'] as Map<String, dynamic>);
  }

  // ==================== COLLABORATORS ====================

  /// Get collaborators for a prayer.
  Future<List<PrayerCollaboratorModel>> getCollaborators(
      String prayerId) async {
    final response = await httpGet('/prayers/$prayerId/collaborators');
    assertSuccess(response, 'Get collaborators');
    final list = parseList(response, 'collaborators');
    return list.map(PrayerCollaboratorModel.fromJson).toList();
  }

  /// Add a collaborator by username. Server resolves the user.
  Future<PrayerCollaboratorModel> addCollaborator({
    required String prayerId,
    required String username,
  }) async {
    final response =
        await httpPost('/prayers/$prayerId/collaborators', body: {
      'username': username,
    });
    assertSuccess(response, 'Add collaborator');
    final body = parseBody(response);
    return PrayerCollaboratorModel.fromJson(
        body['collaborator'] as Map<String, dynamic>);
  }

  /// Update a collaborator's role.
  Future<void> updateCollaboratorRole({
    required String prayerId,
    required String collaboratorId,
    required String role,
  }) async {
    final response = await httpPut(
      '/prayers/$prayerId/collaborators/$collaboratorId/role',
      body: {'role': role},
    );
    assertSuccess(response, 'Update collaborator role');
  }

  /// Remove a collaborator.
  Future<void> removeCollaborator({
    required String prayerId,
    required String collaboratorId,
  }) async {
    final response = await httpDelete(
        '/prayers/$prayerId/collaborators/$collaboratorId');
    assertSuccess(response, 'Remove collaborator');
  }

  // ==================== ANSWERED NOTIFICATION ====================

  /// Notify collaborators that a prayer has been answered.
  ///
  /// Best-effort — callers should catch and ignore errors.
  Future<void> notifyAnswered(String prayerId) async {
    final response = await httpPost(
      '/prayers/$prayerId/notify-answered',
      body: {},
    );
    assertSuccess(response, 'Notify answered');
  }

  // ==================== SHARE CODE LOOKUP ====================

  /// Resolve a share code to the prayer ID it points to.
  ///
  /// Returns null if the share code is not found or has been revoked.
  /// Throws [SocialApiException] for server errors.
  Future<String?> lookupShareCode(String shareCode) async {
    final response = await httpGet('/share/$shareCode');
    if (response.statusCode == 404) return null;
    assertSuccess(response, 'Share code lookup');
    final body = parseBody(response);
    return body['prayerId'] as String?;
  }
}
