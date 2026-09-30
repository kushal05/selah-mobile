// Rules about the string catalogue itself, checked against app_en.arb.
//
// These are the invariants an audit had to find by hand, written down so they
// hold by construction instead. Each one is cheap: the file is 900-odd keys of
// JSON and this reads it once.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _messages() {
  final raw = File('lib/l10n/app_en.arb').readAsStringSync();
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('@') && e.value is String)
        e.key: e.value as String,
  };
}

void main() {
  final messages = _messages();

  test('the catalogue is not empty, so a broken read cannot pass everything', () {
    // Every other test here is a "no offenders" assertion, which an empty map
    // satisfies. This is the one that fails if the file moves or stops parsing.
    expect(messages.length, greaterThan(800));
  });

  test('no value shouts', () {
    // An ALL CAPS value asks a translator to uppercase, which is wrong in
    // scripts without case and inconsistent where the same words appear
    // normally elsewhere — 'PRAYER' was also the trash list's type label, so
    // one row of eight read "PRAYER • 3 days left". Uppercasing belongs in the
    // widget: SectionLabel, SearchSection and the daily-focus eyebrow all do it.
    final shouting = {
      for (final e in messages.entries)
        if (e.value.length > 2 &&
            e.value == e.value.toUpperCase() &&
            e.value != e.value.toLowerCase())
          e.key: e.value,
    };
    expect(shouting, isEmpty,
        reason: 'uppercase these at the render site, not in the ARB');
  });

  test('no section label is shouted at the call site either', () {
    // The companion to the rule above, and the reason it is needed: cleaning
    // ALL CAPS out of the ARB left six SectionLabel('USAGE')-style literals
    // doing the same job in Dart, two of which duplicated keys that had just
    // been made readable. SectionLabel uppercases what it is given, so a
    // pre-shouted argument is redundant, unlocalised, and wrong in a script
    // without case — the same three objections, one layer up.
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final m = RegExp(r"""SectionLabel\(\s*'([^']+)'""").firstMatch(lines[i]);
        if (m == null) continue;
        final text = m.group(1)!;
        if (text == text.toUpperCase() && text != text.toLowerCase()) {
          offenders.add('${file.path}:${i + 1}: ${m.group(1)}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'pass sentence case and let SectionLabel do the uppercasing');
  });

  test('no two keys hold the same words', () {
    // Case-insensitive, because that is how the duplicates got in: `navNotes`
    // "Notes" beside `notes` "NOTES". Each one is a second line for a
    // translator and a chance for the two to drift apart.
    final byValue = <String, List<String>>{};
    for (final e in messages.entries) {
      byValue.putIfAbsent(e.value.trim().toLowerCase(), () => []).add(e.key);
    }
    final dupes = {
      for (final e in byValue.entries)
        if (e.value.length > 1) e.key: e.value,
    };
    // The trash labels are the deliberate exception: they read mid-sentence
    // ("Move 3 prayers to trash"), so they are lowercase where the navigation
    // label is capitalised. Same words, genuinely different forms.
    dupes.removeWhere(
        (_, keys) => keys.any((k) => k.startsWith('trashLabel')));
    expect(dupes, isEmpty,
        reason: 'merge these onto one key and update the call sites');
  });

  test('no key was cut off and numbered by the generator', () {
    // `nkjvIsDownloadedOnFirstLaunchDownloadAdditio2` — cut mid-word and given
    // a digit because the truncation collided with another key. Four of those
    // existed and all four are now named for what they are.
    //
    // Deliberately NOT a length limit. Keys derived from their own English is
    // the convention across all 900-odd of them, and a good number are clipped
    // mid-word at the generator's width — `…AreYouSureYouWantToDisc`. Renaming
    // those is churn against the house style, so they are out of scope, and a
    // cap set just above them would be a rule that passes because of where the
    // number was put rather than because the catalogue is clean. The generator
    // suffix is the part that was a defect, so the generator suffix is the part
    // this enforces.
    // Long *and* digit-suffixed. Both halves matter: the length is what makes
    // it a truncated sentence rather than a short name, and the digit is the
    // collision marker. A regex over letter runs cannot do this — camelCase has
    // no long lowercase run, and one of the four had a digit in the middle
    // (`…FreesUp8Mb…`), so both spellings I tried first matched nothing at all
    // and the rule sat green over an empty check.
    final numbered = [
      for (final k in messages.keys)
        if (k.length >= 30 && RegExp(r'\d$').hasMatch(k)) k,
    ];
    expect(numbered, isEmpty,
        reason: 'name these for what they are, not for what they say');
  });

  test('every error message says what to do next', () {
    // "Search failed" is a dead end with punctuation. Field labels are exempt:
    // they name a value rather than telling the user something went wrong.
    const labels = {'lastError', 'syncError', 'unableToFetch', 'unknownError'};
    final errorish = RegExp(
        r"^(failed|could ?not|couldn't|unable|error|invalid|cannot|can't)",
        caseSensitive: false);
    final nextStep = RegExp(
        r'try again|try another|check your|check it|check the|reconnect|'
        r'sign in again|tap |then |re-?download|contact |restart|below|'
        r'saved on this device',
        caseSensitive: false);

    final deadEnds = {
      for (final e in messages.entries)
        if (!labels.contains(e.key) &&
            errorish.hasMatch(e.value.trim()) &&
            !nextStep.hasMatch(e.value))
          e.key: e.value,
    };
    expect(deadEnds, isEmpty,
        reason: 'add the next step, or add the key to the label exemptions');
  });
}
