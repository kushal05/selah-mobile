#!/usr/bin/env python3
"""Zefania XML -> per-translation Bible .db generator.

Produces a standalone per-version Bible SQLite database with the SAME schema as
the bundled `assets/bible.db` (see `lib/features/bible/data/bible_schema_ddl.dart`,
schema_version 2). The output is the kind of file uploaded to S3 and merged into a
user's `bible.db` via ATTACH + INSERT OR IGNORE in `BibleDatabaseService`.

Input format (Zefania XML):
    <XMLBIBLE>
      <BIBLEBOOK bnumber="1" bname="Genesis">
        <CHAPTER cnumber="1">
          <VERS vnumber="1">...verse text...</VERS>

`bnumber` must be the canonical book number 1..66 (Genesis..Revelation).

Usage:
    python tools/generate_zefania_db.py <input.xml> <output.db> <TRANSLATION_CODE>

Example:
    python tools/generate_zefania_db.py telugu_bsi.xml TELUGU.db TELUGU

The TRANSLATION_CODE is written into every `bible_verses.translation` value and
MUST match the `code` registered in the `bible_versions` table (selah-api
migration), because the app deletes a version via `WHERE translation = code`.
"""

import sqlite3
import sys
import xml.etree.ElementTree as ET

# Schema version — keep in sync with bibleSchemaVersion in bible_schema_ddl.dart.
SCHEMA_VERSION = 2

# Canonical book metadata: (id, name, short_name, testament). testament 0=OT 1=NT.
# Mirrors _bookMetadata in tools/generate_bible_db.dart.
BOOK_METADATA = [
    (1, "Genesis", "Gen", 0), (2, "Exodus", "Exod", 0), (3, "Leviticus", "Lev", 0),
    (4, "Numbers", "Num", 0), (5, "Deuteronomy", "Deut", 0), (6, "Joshua", "Josh", 0),
    (7, "Judges", "Judg", 0), (8, "Ruth", "Ruth", 0), (9, "1 Samuel", "1Sam", 0),
    (10, "2 Samuel", "2Sam", 0), (11, "1 Kings", "1Kgs", 0), (12, "2 Kings", "2Kgs", 0),
    (13, "1 Chronicles", "1Chr", 0), (14, "2 Chronicles", "2Chr", 0), (15, "Ezra", "Ezra", 0),
    (16, "Nehemiah", "Neh", 0), (17, "Esther", "Esth", 0), (18, "Job", "Job", 0),
    (19, "Psalms", "Ps", 0), (20, "Proverbs", "Prov", 0), (21, "Ecclesiastes", "Eccl", 0),
    (22, "Song of Solomon", "Song", 0), (23, "Isaiah", "Isa", 0), (24, "Jeremiah", "Jer", 0),
    (25, "Lamentations", "Lam", 0), (26, "Ezekiel", "Ezek", 0), (27, "Daniel", "Dan", 0),
    (28, "Hosea", "Hos", 0), (29, "Joel", "Joel", 0), (30, "Amos", "Amos", 0),
    (31, "Obadiah", "Obad", 0), (32, "Jonah", "Jonah", 0), (33, "Micah", "Mic", 0),
    (34, "Nahum", "Nah", 0), (35, "Habakkuk", "Hab", 0), (36, "Zephaniah", "Zeph", 0),
    (37, "Haggai", "Hag", 0), (38, "Zechariah", "Zech", 0), (39, "Malachi", "Mal", 0),
    (40, "Matthew", "Matt", 1), (41, "Mark", "Mark", 1), (42, "Luke", "Luke", 1),
    (43, "John", "John", 1), (44, "Acts", "Acts", 1), (45, "Romans", "Rom", 1),
    (46, "1 Corinthians", "1Cor", 1), (47, "2 Corinthians", "2Cor", 1), (48, "Galatians", "Gal", 1),
    (49, "Ephesians", "Eph", 1), (50, "Philippians", "Phil", 1), (51, "Colossians", "Col", 1),
    (52, "1 Thessalonians", "1Thess", 1), (53, "2 Thessalonians", "2Thess", 1),
    (54, "1 Timothy", "1Tim", 1), (55, "2 Timothy", "2Tim", 1), (56, "Titus", "Titus", 1),
    (57, "Philemon", "Phlm", 1), (58, "Hebrews", "Heb", 1), (59, "James", "Jas", 1),
    (60, "1 Peter", "1Pet", 1), (61, "2 Peter", "2Pet", 1), (62, "1 John", "1John", 1),
    (63, "2 John", "2John", 1), (64, "3 John", "3John", 1), (65, "Jude", "Jude", 1),
    (66, "Revelation", "Rev", 1),
]
VALID_BOOK_IDS = {b[0] for b in BOOK_METADATA}

# Exact DDL from bible_schema_ddl.dart (schema_version 2).
SCHEMA_DDL = [
    "CREATE TABLE IF NOT EXISTS _meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
    """CREATE TABLE IF NOT EXISTS bible_books (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, short_name TEXT NOT NULL,
        testament INTEGER NOT NULL, sort_order INTEGER NOT NULL)""",
    """CREATE TABLE IF NOT EXISTS bible_verses (
        id INTEGER PRIMARY KEY AUTOINCREMENT, translation TEXT NOT NULL,
        book_id INTEGER NOT NULL REFERENCES bible_books(id),
        chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL,
        UNIQUE(translation, book_id, chapter, verse))""",
    """CREATE VIRTUAL TABLE IF NOT EXISTS bible_verses_fts USING fts5(
        text, content='bible_verses', content_rowid='id', prefix='2 3 4')""",
    "CREATE INDEX IF NOT EXISTS idx_verse_lookup ON bible_verses(book_id, chapter, verse)",
    "CREATE INDEX IF NOT EXISTS idx_books_testament ON bible_books(testament, sort_order)",
    """CREATE TRIGGER IF NOT EXISTS bible_verses_ai AFTER INSERT ON bible_verses BEGIN
        INSERT INTO bible_verses_fts(rowid, text) VALUES (new.id, new.text); END""",
    """CREATE TRIGGER IF NOT EXISTS bible_verses_ad AFTER DELETE ON bible_verses BEGIN
        INSERT INTO bible_verses_fts(bible_verses_fts, rowid, text)
          VALUES ('delete', old.id, old.text); END""",
    """CREATE TRIGGER IF NOT EXISTS bible_verses_au AFTER UPDATE ON bible_verses BEGIN
        INSERT INTO bible_verses_fts(bible_verses_fts, rowid, text)
          VALUES ('delete', old.id, old.text);
        INSERT INTO bible_verses_fts(rowid, text) VALUES (new.id, new.text); END""",
]


def main():
    if len(sys.argv) != 4:
        print("Usage: python tools/generate_zefania_db.py <input.xml> <output.db> <CODE>")
        sys.exit(1)

    xml_path, db_path, code = sys.argv[1], sys.argv[2], sys.argv[3]

    print(f"Parsing {xml_path} ...")
    root = ET.parse(xml_path).getroot()

    import os
    if os.path.exists(db_path):
        os.remove(db_path)

    db = sqlite3.connect(db_path)
    try:
        cur = db.cursor()
        for ddl in SCHEMA_DDL:
            cur.execute(ddl)
        cur.execute("INSERT INTO _meta(key, value) VALUES('schema_version', ?)",
                    (str(SCHEMA_VERSION),))
        cur.executemany(
            "INSERT INTO bible_books(id, name, short_name, testament, sort_order) "
            "VALUES(?,?,?,?,?)",
            [(b[0], b[1], b[2], b[3], b[0]) for b in BOOK_METADATA],
        )

        rows = []
        for book in root.findall("BIBLEBOOK"):
            bnum = int(book.get("bnumber"))
            if bnum not in VALID_BOOK_IDS:
                print(f"  WARNING: skipping non-canonical book bnumber={bnum} "
                      f"({book.get('bname')})")
                continue
            for chapter in book.findall("CHAPTER"):
                cnum = int(chapter.get("cnumber"))
                for vers in chapter.findall("VERS"):
                    vnum = int(vers.get("vnumber"))
                    text = "".join(vers.itertext()).strip()
                    if not text:
                        continue
                    rows.append((code, bnum, cnum, vnum, text))

        cur.executemany(
            "INSERT INTO bible_verses(translation, book_id, chapter, verse, text) "
            "VALUES(?,?,?,?,?)",
            rows,
        )
        db.commit()
        cur.execute("VACUUM")
        db.commit()

        verse_count = cur.execute("SELECT COUNT(*) FROM bible_verses").fetchone()[0]
        fts_count = cur.execute("SELECT COUNT(*) FROM bible_verses_fts").fetchone()[0]
        book_count = cur.execute("SELECT COUNT(*) FROM bible_books").fetchone()[0]
        translations = [r[0] for r in cur.execute(
            "SELECT DISTINCT translation FROM bible_verses").fetchall()]

        print(f"  Books:        {book_count}")
        print(f"  Verses:       {verse_count}")
        print(f"  FTS entries:  {fts_count}")
        print(f"  Translation:  {translations}")
        if verse_count != fts_count:
            print("  WARNING: FTS count != verse count!")

        size_mb = os.path.getsize(db_path) / 1024 / 1024
        print(f"  Output:       {db_path} ({size_mb:.1f} MB)")
    finally:
        db.close()


if __name__ == "__main__":
    main()
