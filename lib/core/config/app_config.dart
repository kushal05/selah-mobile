/// Compile-time application configuration, injected via --dart-define-from-file.
///
/// Build commands:
///   flutter run  --flavor qa         --dart-define-from-file=flavors/qa.json
///   flutter run  --flavor production --dart-define-from-file=flavors/production.json
///   flutter build apk --flavor qa   --dart-define-from-file=flavors/qa.json
class AppConfig {
  const AppConfig._();

  /// Active flavor: 'production' | 'qa'
  static const String flavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'production',
  );

  /// Display name shown on the home screen icon and title bar.
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Selah',
  );

  /// Base URL for the sync REST API.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.selahapp.in',
  );

  /// Google OAuth Web Client ID (used by google_sign_in to obtain an ID token).
  /// This must be the **Web** client ID from Google Cloud Console, not Android.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Local SQLite database file name.
  /// Each flavor uses a different file so prod and QA data never mix.
  static const String dbName = String.fromEnvironment(
    'DB_NAME',
    defaultValue: 'selah-prod_sync.db',
  );

  /// S3 URL to the OTA metadata.json file.
  /// When set, the app fetches updates directly from S3 instead of the backend.
  /// Leave empty to use the legacy backend /v1/app/version endpoint.
  static const String updateMetadataUrl = String.fromEnvironment(
    'UPDATE_METADATA_URL',
    defaultValue: '',
  );

  /// S3 URL to the OTA manifest.json file (rolling list of recent builds).
  /// Derived from [updateMetadataUrl] by swapping the `metadata` filename for
  /// `manifest`, since both files live alongside each other under the same
  /// `app-updates/` prefix and the build script writes them in lockstep.
  static String get updateManifestUrl {
    if (updateMetadataUrl.isEmpty) return '';
    return updateMetadataUrl
        .replaceAll('metadata-qa.json', 'manifest-qa.json')
        .replaceAll('metadata.json', 'manifest.json');
  }

  /// Fallback CDN URL for the initial Bible database download.
  /// @deprecated — download URLs are now returned by GET /v1/bible/versions
  /// and this field is no longer read by the app. Kept for emergency fallback.
  static const String bibleDbUrl = String.fromEnvironment(
    'BIBLE_DB_URL',
    defaultValue: '',
  );

  static bool get isProduction => flavor == 'production';
  static bool get isQA => flavor == 'qa';
}
