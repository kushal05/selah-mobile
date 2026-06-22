/// Pure-function chord transposition engine.
///
/// Supports major chords, minor chords, sharps (#), flats (b),
/// and all common modifiers (7, m7, maj7, sus2, sus4, dim, aug, add9, etc.).
/// Transposition is deterministic and never mutates stored data.
class ChordTransposer {
  ChordTransposer._();

  // Chromatic scale using sharps (canonical representation)
  static const _sharpNotes = [
    'C', 'C#', 'D', 'D#', 'E', 'F',
    'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  // Chromatic scale using flats
  static const _flatNotes = [
    'C', 'Db', 'D', 'Eb', 'E', 'F',
    'Gb', 'G', 'Ab', 'A', 'Bb', 'B',
  ];

  // Map every note name (sharp & flat variants) to its semitone index 0..11
  static final Map<String, int> _noteToSemitone = {
    'C': 0, 'B#': 0,
    'C#': 1, 'Db': 1,
    'D': 2,
    'D#': 3, 'Eb': 3,
    'E': 4, 'Fb': 4,
    'F': 5, 'E#': 5,
    'F#': 6, 'Gb': 6,
    'G': 7,
    'G#': 8, 'Ab': 8,
    'A': 9,
    'A#': 10, 'Bb': 10,
    'B': 11, 'Cb': 11,
  };

  // Keys that conventionally use flats
  static const _flatKeys = {'F', 'Bb', 'Eb', 'Ab', 'Db', 'Gb'};

  /// Transpose a single chord symbol by [semitones] half-steps.
  ///
  /// Preserves modifiers (m, 7, maj7, sus4, dim, aug, etc.).
  /// [preferFlats] controls whether the output uses sharps or flats.
  /// If null, the decision is based on the original chord's accidental.
  static String transposeChord(String chord, int semitones, {bool? preferFlats}) {
    if (chord.trim().isEmpty) return chord;

    // Parse root note: first char is A-G, optional second char is # or b
    final match = RegExp(r'^([A-Ga-g])([#b]?)(.*)$').firstMatch(chord.trim());
    if (match == null) return chord; // not a valid chord, return as-is

    final rootLetter = match.group(1)!.toUpperCase();
    final accidental = match.group(2)!;
    final modifier = match.group(3)!; // everything after the root note

    final rootName = '$rootLetter$accidental';
    final semitone = _noteToSemitone[rootName];
    if (semitone == null) return chord; // unknown note

    // Dart's % on positive divisor always returns non-negative, so no extra guard needed
    final normalizedSemitone = (semitone + semitones) % 12;

    // Decide sharp vs flat: use caller preference, or fall back to original accidental
    final useFlats = preferFlats ?? (accidental == 'b');
    final noteList = useFlats ? _flatNotes : _sharpNotes;

    // Handle slash chords (e.g. G/B) — transpose the bass note too
    final slashIndex = modifier.indexOf('/');
    if (slashIndex >= 0 && slashIndex + 1 < modifier.length) {
      final prefix = modifier.substring(0, slashIndex); // e.g. "m" from "m/B"
      final bassChord = modifier.substring(slashIndex + 1); // e.g. "B"
      final transposedBass = transposeChord(bassChord, semitones, preferFlats: useFlats ? true : null);
      return '${noteList[normalizedSemitone]}$prefix/$transposedBass';
    }

    return '${noteList[normalizedSemitone]}$modifier';
  }

  /// Transpose a full chord line (space-separated chords) by [semitones].
  static String transposeLine(String line, int semitones, {bool? preferFlats}) {
    if (semitones == 0) return line;
    // Split on whitespace, preserving multiple spaces for alignment
    return line.replaceAllMapped(
      RegExp(r'[A-Ga-g][#b]?[^\s]*'),
      (match) => transposeChord(match.group(0)!, semitones, preferFlats: preferFlats),
    );
  }

  /// Transpose a scale/key name by [semitones].
  /// E.g. transposeKey("Dm", 2) => "Em", transposeKey("G", -3) => "E"
  static String transposeKey(String key, int semitones, {bool? preferFlats}) {
    if (key.isEmpty || semitones == 0) return key;
    return transposeChord(key, semitones, preferFlats: preferFlats);
  }

  /// Determine whether a key conventionally uses flats.
  static bool keyUsesFlats(String key) {
    if (key.isEmpty) return false;
    // Extract the root note (first 1-2 chars)
    final match = RegExp(r'^([A-G][#b]?)').firstMatch(key);
    if (match == null) return false;
    return _flatKeys.contains(match.group(1));
  }

  /// Get all 12 chromatic key names (for scale picker UI).
  /// Returns both major and common minor variants.
  static const majorKeys = [
    'C', 'C#', 'D', 'Eb', 'E', 'F',
    'F#', 'G', 'Ab', 'A', 'Bb', 'B',
  ];

  static const minorKeys = [
    'Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm',
    'F#m', 'Gm', 'Abm', 'Am', 'Bbm', 'Bm',
  ];

  static const allKeys = [
    '', // no key set
    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
    'Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'Abm', 'Am', 'Bbm', 'Bm',
  ];
}
