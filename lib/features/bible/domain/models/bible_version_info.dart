/// Bible version metadata model.
///
/// Previously this file contained a hardcoded [kBibleVersions] constant.
/// That registry has been replaced by [BibleVersionStates] in the local
/// Drift database, populated at runtime from GET /v1/bible/versions.
///
/// This class is kept as a lightweight view model used in presentation code.
/// Instances are constructed from [BibleVersionState] rows via
/// [BibleVersionInfo.fromRow].
library;

import '../../../../core/database/sync_database.dart';

class BibleVersionInfo {
  final String code;
  final String name;
  final String downloadUrl;
  final int approximateSizeMb;
  final int sortOrder;

  /// Whether this is the user's chosen default translation.
  final bool isDefault;

  /// Whether verses for this translation exist in the local bible.db.
  /// Derived externally from [BibleRepository.getAvailableTranslations].
  final bool isDownloaded;

  const BibleVersionInfo({
    required this.code,
    required this.name,
    required this.downloadUrl,
    required this.approximateSizeMb,
    required this.sortOrder,
    required this.isDefault,
    required this.isDownloaded,
  });

  factory BibleVersionInfo.fromRow(
    BibleVersionState row, {
    required bool isDownloaded,
  }) {
    return BibleVersionInfo(
      code: row.code,
      name: row.name,
      downloadUrl: row.downloadUrl,
      approximateSizeMb: row.approximateSizeMb,
      sortOrder: row.sortOrder,
      isDefault: row.isDefault,
      isDownloaded: isDownloaded,
    );
  }
}

/// Default translation code used when no user preference has been set.
const String kDefaultBibleVersionCode = 'NKJV';

/// Returns the uppercased translation code as a display label (e.g. 'NKJV').
///
/// Call sites that have a [BibleVersionInfo] object should use [info.name]
/// directly for the full display name.
String bibleVersionDisplayName(String code) => code.toUpperCase();
