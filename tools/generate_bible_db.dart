// ignore_for_file: avoid_print

/// Bible Database Generator
///
/// Standalone Dart script that creates the pre-populated `bible.db` file
/// bundled in `assets/`. Run this script on a development machine, then
/// commit the resulting `assets/bible.db` to the repository.
///
/// Usage:
///   `dart run tools/generate_bible_db.dart <translations_dir> [translation...]`
///
/// Examples:
///   # All translation folders found in the directory:
///   dart run tools/generate_bible_db.dart ../bible-translations
///
///   # Specific translations only:
///   dart run tools/generate_bible_db.dart ../bible-translations NKJV NLT
///
/// Prerequisites:
///   - The `sqlite3` package must be available (it's a project dependency).
///   - A bible-translations directory with combined bible JSON files:
///       bible-translations/
///         NKJV/
///           NKJV_bible.json  →  {"Genesis": {"1": {"1": "text", ...}}, "Exodus": {...}, ...}
///         NLT/
///           NLT_bible.json   →  {"Genesis": {"1": {"1": "text", ...}}, "Exodus": {...}, ...}
///         ...
///
///   Each combined JSON file has book names as top-level keys, with chapters
///   as string keys and verses as string keys mapping to text.
///
/// Output:
///   assets/bible.db — ready to bundle via pubspec.yaml
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:notify/features/bible/data/bible_schema_ddl.dart';

/// Book metadata: (canonical order, full name, short name, testament)
/// testament: 0 = OT, 1 = NT
const List<(int, String, String, int)> _bookMetadata = [
  // Old Testament
  (1, 'Genesis', 'Gen', 0),
  (2, 'Exodus', 'Exod', 0),
  (3, 'Leviticus', 'Lev', 0),
  (4, 'Numbers', 'Num', 0),
  (5, 'Deuteronomy', 'Deut', 0),
  (6, 'Joshua', 'Josh', 0),
  (7, 'Judges', 'Judg', 0),
  (8, 'Ruth', 'Ruth', 0),
  (9, '1 Samuel', '1Sam', 0),
  (10, '2 Samuel', '2Sam', 0),
  (11, '1 Kings', '1Kgs', 0),
  (12, '2 Kings', '2Kgs', 0),
  (13, '1 Chronicles', '1Chr', 0),
  (14, '2 Chronicles', '2Chr', 0),
  (15, 'Ezra', 'Ezra', 0),
  (16, 'Nehemiah', 'Neh', 0),
  (17, 'Esther', 'Esth', 0),
  (18, 'Job', 'Job', 0),
  (19, 'Psalms', 'Ps', 0),
  (20, 'Proverbs', 'Prov', 0),
  (21, 'Ecclesiastes', 'Eccl', 0),
  (22, 'Song of Solomon', 'Song', 0),
  (23, 'Isaiah', 'Isa', 0),
  (24, 'Jeremiah', 'Jer', 0),
  (25, 'Lamentations', 'Lam', 0),
  (26, 'Ezekiel', 'Ezek', 0),
  (27, 'Daniel', 'Dan', 0),
  (28, 'Hosea', 'Hos', 0),
  (29, 'Joel', 'Joel', 0),
  (30, 'Amos', 'Amos', 0),
  (31, 'Obadiah', 'Obad', 0),
  (32, 'Jonah', 'Jonah', 0),
  (33, 'Micah', 'Mic', 0),
  (34, 'Nahum', 'Nah', 0),
  (35, 'Habakkuk', 'Hab', 0),
  (36, 'Zephaniah', 'Zeph', 0),
  (37, 'Haggai', 'Hag', 0),
  (38, 'Zechariah', 'Zech', 0),
  (39, 'Malachi', 'Mal', 0),
  // New Testament
  (40, 'Matthew', 'Matt', 1),
  (41, 'Mark', 'Mark', 1),
  (42, 'Luke', 'Luke', 1),
  (43, 'John', 'John', 1),
  (44, 'Acts', 'Acts', 1),
  (45, 'Romans', 'Rom', 1),
  (46, '1 Corinthians', '1Cor', 1),
  (47, '2 Corinthians', '2Cor', 1),
  (48, 'Galatians', 'Gal', 1),
  (49, 'Ephesians', 'Eph', 1),
  (50, 'Philippians', 'Phil', 1),
  (51, 'Colossians', 'Col', 1),
  (52, '1 Thessalonians', '1Thess', 1),
  (53, '2 Thessalonians', '2Thess', 1),
  (54, '1 Timothy', '1Tim', 1),
  (55, '2 Timothy', '2Tim', 1),
  (56, 'Titus', 'Titus', 1),
  (57, 'Philemon', 'Phlm', 1),
  (58, 'Hebrews', 'Heb', 1),
  (59, 'James', 'Jas', 1),
  (60, '1 Peter', '1Pet', 1),
  (61, '2 Peter', '2Pet', 1),
  (62, '1 John', '1John', 1),
  (63, '2 John', '2John', 1),
  (64, '3 John', '3John', 1),
  (65, 'Jude', 'Jude', 1),
  (66, 'Revelation', 'Rev', 1),
];

/// Name aliases for book names that differ between data sources and our
/// canonical names. Keys are lowercase.
const Map<String, String> _bookNameAliases = {
  'psalm': 'Psalms',
  'song of solomon': 'Song of Solomon',
};

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart run tools/generate_bible_db.dart <translations_dir> [translation...]');
    print('');
    print('Examples:');
    print('  dart run tools/generate_bible_db.dart ../bible-translations');
    print('  dart run tools/generate_bible_db.dart ../bible-translations NKJV NLT');
    exit(1);
  }

  final translationsDir = Directory(args.first);
  if (!translationsDir.existsSync()) {
    print('ERROR: Directory not found: ${args.first}');
    exit(1);
  }

  // Determine which translations to process
  final requestedTranslations = args.length > 1 ? args.sublist(1) : null;
  final translationFiles = _discoverTranslations(translationsDir, requestedTranslations);

  if (translationFiles.isEmpty) {
    print('ERROR: No translation JSON files found in ${args.first}');
    exit(1);
  }

  final outputPath = 'assets/bible.db';

  print('Bible Database Generator');
  print('========================');
  print('Source:       ${translationsDir.path}');
  print('Translations: ${translationFiles.keys.join(', ')}');
  print('Output:       $outputPath');
  print('');

  // Delete existing output if present
  final outFile = File(outputPath);
  if (outFile.existsSync()) {
    outFile.deleteSync();
    print('Deleted existing $outputPath');
  }

  // Create the database
  final db = sqlite3.open(outputPath);

  try {
    // Create schema
    print('Creating schema...');
    for (final ddl in bibleSchemaDDL) {
      db.execute(ddl);
    }

    // Insert schema version
    db.execute(
      "INSERT INTO _meta (key, value) VALUES ('schema_version', '$bibleSchemaVersion')",
    );

    // Insert book metadata
    print('Inserting book metadata (66 books)...');
    final bookStmt = db.prepare(
      'INSERT INTO bible_books (id, name, short_name, testament, sort_order) '
      'VALUES (?, ?, ?, ?, ?)',
    );
    for (final (id, name, shortName, testament) in _bookMetadata) {
      bookStmt.execute([id, name, shortName, testament, id]);
    }
    bookStmt.dispose();

    // Build name → id lookup (lowercase canonical + aliases)
    final nameToId = <String, int>{};
    for (final (id, name, _, _) in _bookMetadata) {
      nameToId[name.toLowerCase()] = id;
    }
    for (final entry in _bookNameAliases.entries) {
      final canonicalId = nameToId[entry.value.toLowerCase()];
      if (canonicalId != null) {
        nameToId[entry.key] = canonicalId;
      }
    }

    // Process each translation
    var grandTotal = 0;

    final verseStmt = db.prepare(
      'INSERT INTO bible_verses (translation, book_id, chapter, verse, text) '
      'VALUES (?, ?, ?, ?, ?)',
    );

    for (final entry in translationFiles.entries) {
      final translationName = entry.key;
      final bibleFile = entry.value;

      print('');
      print('--- $translationName ---');

      final translationTotal = _processTranslation(
        db: db,
        verseStmt: verseStmt,
        translationName: translationName,
        bibleFile: bibleFile,
        nameToId: nameToId,
      );

      grandTotal += translationTotal;
      print('  Total: $translationTotal verses');
    }

    verseStmt.dispose();

    print('');
    print('Grand total verses inserted: $grandTotal');

    // Verify
    final bookCount =
        db.select('SELECT COUNT(*) as c FROM bible_books').first['c'] as int;
    final verseCount =
        db.select('SELECT COUNT(*) as c FROM bible_verses').first['c'] as int;
    final ftsCount =
        db.select('SELECT COUNT(*) as c FROM bible_verses_fts').first['c'] as int;
    final translationList = db
        .select('SELECT DISTINCT translation FROM bible_verses ORDER BY translation')
        .map((r) => r['translation'] as String)
        .toList();

    print('');
    print('Verification:');
    print('  Books:        $bookCount');
    print('  Verses:       $verseCount');
    print('  FTS entries:  $ftsCount');
    print('  Translations: ${translationList.join(', ')}');

    if (verseCount != ftsCount) {
      print('  WARNING: FTS count does not match verse count!');
    }

    // Per-translation breakdown
    for (final t in translationList) {
      final count = db
          .select(
            'SELECT COUNT(*) as c FROM bible_verses WHERE translation = ?',
            [t],
          )
          .first['c'] as int;
      print('    $t: $count verses');
    }

    // Compact the database
    db.execute('VACUUM');
    print('');
    print('Database compacted (VACUUM).');

    final fileSize = File(outputPath).lengthSync();
    print(
      'Output file size: ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB',
    );
    print('');
    print('Done. The file at $outputPath is ready to bundle.');
  } finally {
    db.dispose();
  }
}

/// Discover combined bible JSON files under [root].
///
/// Each translation is expected at `<root>/<NAME>/<NAME>_bible.json`.
/// If [only] is provided, only those translation names are included.
///
/// Returns a map of translation name → combined bible JSON file.
Map<String, File> _discoverTranslations(
  Directory root,
  List<String>? only,
) {
  final results = <String, File>{};

  for (final entity in root.listSync().whereType<Directory>()) {
    final name = entity.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .last;

    // Skip hidden/system dirs
    if (name.startsWith('.') || name.startsWith('_')) continue;

    // Check for <NAME>_bible.json file
    final bibleFile = File('${entity.path}/${name}_bible.json');
    if (!bibleFile.existsSync()) continue;

    // Filter to requested translations if specified
    if (only != null && !only.any((t) => t.toUpperCase() == name.toUpperCase())) {
      continue;
    }

    results[name.toUpperCase()] = bibleFile;
  }

  return results;
}

/// Process a combined bible JSON file for a single translation.
///
/// Returns the total number of verses inserted.
int _processTranslation({
  required Database db,
  required PreparedStatement verseStmt,
  required String translationName,
  required File bibleFile,
  required Map<String, int> nameToId,
}) {
  db.execute('BEGIN TRANSACTION');

  var totalVerses = 0;
  final jsonStr = bibleFile.readAsStringSync();
  final data = jsonDecode(jsonStr) as Map<String, dynamic>;

  for (final bookEntry in data.entries) {
    final bookName = bookEntry.key;

    // Resolve book name to canonical ID
    final lookupName = bookName.toLowerCase();
    final bookId = nameToId[lookupName];
    if (bookId == null) {
      print('  WARNING: Unknown book "$bookName", skipping.');
      continue;
    }

    final chapters = bookEntry.value as Map<String, dynamic>;
    var bookVerses = 0;

    // Chapters are string keys ("1", "2", ...) mapping to verse maps
    final sortedChapters = chapters.keys.toList()
      ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    for (final chapterKey in sortedChapters) {
      final chapterNum = int.parse(chapterKey);
      final verses = chapters[chapterKey] as Map<String, dynamic>;

      final sortedVerses = verses.keys.toList()
        ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

      for (final verseKey in sortedVerses) {
        final verseNum = int.parse(verseKey);
        final verseText = (verses[verseKey] as String).trim();
        if (verseText.isEmpty) continue;

        verseStmt.execute([
          translationName,
          bookId,
          chapterNum,
          verseNum,
          verseText,
        ]);
        bookVerses++;
      }
    }

    totalVerses += bookVerses;

    // Find canonical name for display
    final canonicalName = _bookMetadata
        .where((m) => m.$1 == bookId)
        .first
        .$2;
    print('  $canonicalName: $bookVerses verses');
  }

  db.execute('COMMIT');
  return totalVerses;
}
