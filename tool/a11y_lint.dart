// Accessibility lint for lib/.
//
// Guards the two regression categories that made large parts of the app
// unreachable to screen readers. Both are invisible in review and neither is
// caught by `flutter analyze`, so they are checked here instead.
//
//   1. IconButton without a `tooltip:`
//      The tooltip is what Flutter promotes into the button's accessible name.
//      Without one, TalkBack and VoiceOver announce a bare "button".
//
//   2. Semantics with `excludeSemantics: true` but no `onTap:`
//      excludeSemantics drops the subtree's semantics, including the tap
//      action from the GestureDetector or InkWell inside. The control is then
//      announced as a button that cannot be activated — the same end state as
//      (3), reached from the opposite direction.
//
//   3. GestureDetector with `onTapUp:` but no `onTap:`
//      Only `onTap` contributes a tap action to the semantics tree. A control
//      wired solely to `onTapUp` is visible but cannot be activated by a
//      screen reader — it looks fine and is completely unusable.
//
//      A GestureDetector that merely decorates a real button (driving a press
//      animation around an ElevatedButton, say) is fine: the button underneath
//      supplies the semantics. Those are skipped — see [_wrapsARealButton].
//
// Usage:
//   dart run tool/a11y_lint.dart          # report and exit non-zero on any hit
//   dart run tool/a11y_lint.dart --list   # report only, always exit 0

import 'dart:io';

void main(List<String> args) {
  final reportOnly = args.contains('--list');
  final lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('a11y_lint: run this from the package root (no lib/ here).');
    exit(2);
  }

  final findings = <_Finding>[];
  final files = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final src = file.readAsStringSync();
    for (final call in _callsTo('IconButton', src)) {
      if (!call.body.contains('tooltip:')) {
        findings.add(_Finding(file.path, call.line,
            'IconButton has no tooltip: — it announces as an unlabelled "button".'));
      }
    }
    for (final call in _callsTo('Semantics', src)) {
      if (call.body.contains('excludeSemantics: true') &&
          !call.body.contains('onTap:') &&
          !call.body.contains('onLongPress:') &&
          // A non-interactive grouping node has nothing to activate.
          (call.body.contains('button: true') ||
              call.body.contains('link: true'))) {
        findings.add(_Finding(file.path, call.line,
            'Semantics marks this a button and sets excludeSemantics: true '
            'but declares no onTap: — the child tap action is dropped, so a '
            'screen reader can announce it but not activate it.'));
      }
    }
    // 4. A user-facing string written as a literal rather than looked up.
    //    The app carried 1,088 of these while the localisation
    //    infrastructure sat unused, which made it look translatable when it
    //    was not. Config files with no BuildContext are exempt.
    if (!_exemptFromL10n(file.path)) {
      for (final m in _hardcodedStrings.allMatches(src)) {
        if (_isInsideCommentOrString(src, m.start)) continue;
        // Punctuation and separators ("• ", " · ", "…") are not prose and
        // have nothing to translate.
        if (!_hasWords.hasMatch(m.group(2)!)) continue;
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        // A documented per-site exemption beats growing the file list: it
        // keeps the rest of the file linted and states the reason in place.
        if (_suppressedAt(src, line)) continue;
        findings.add(_Finding(file.path, line,
            'User-facing string "${m.group(2)}" is a literal — use '
            'l10n(context).<key> so it can be translated.'));
      }
    }

    // 5. A Scaffold with neither an AppBar nor a SafeArea.
    //    Phones have notches, Dynamic Islands, hole-punch cameras and gesture
    //    bars. An AppBar insets itself and a SafeArea insets its child; a
    //    Scaffold with neither draws its content into whatever the hardware
    //    occupies. Today every such screen happens to centre its content, so
    //    nothing is clipped — that is a property of the content, not a
    //    guarantee, and the next full-bleed screen inherits nothing.
    // `AppScaffold(` contains `Scaffold(`, so this needs a word boundary —
    // without one the router itself was reported.
    //
    // Known limit: the appBar/SafeArea check is file-wide, not per-Scaffold.
    // Six files hold more than one Scaffold (loading and error states beside
    // the real screen), and there one protected Scaffold vouches for the
    // rest. Tightening it means tracking each Scaffold's own argument list,
    // which this scanner is not built for; the file-level rule still catches
    // the case that matters — a whole screen with no protection at all.
    final scaffold = RegExp(r'(?<![A-Za-z0-9_])Scaffold\(').firstMatch(src);
    if (scaffold != null &&
        !src.contains('appBar:') &&
        !src.contains('SafeArea(') &&
        !_exemptFromSafeArea(file.path)) {
      final line =
          '\n'.allMatches(src.substring(0, scaffold.start)).length + 1;
      findings.add(_Finding(file.path, line,
          'Scaffold has neither an appBar: nor a SafeArea — its content can '
          'render under the status bar, a camera cutout or the gesture bar.'));
    }

    for (final call in _callsTo('GestureDetector', src)) {
      if (call.body.contains('onTapUp:') &&
          !call.body.contains('onTap:') &&
          !_wrapsARealButton(call.body)) {
        findings.add(_Finding(file.path, call.line,
            'GestureDetector uses onTapUp: without onTap: — no tap action '
            'reaches the semantics tree, so screen readers cannot activate it.'));
      }
    }
  }

  if (findings.isEmpty) {
    stdout.writeln('a11y_lint: no issues in ${files.length} files.');
    exit(0);
  }

  for (final f in findings) {
    stdout.writeln('${f.path}:${f.line}  ${f.message}');
  }
  stdout.writeln('\na11y_lint: ${findings.length} issue(s).');
  exit(reportOnly ? 0 : 1);
}

/// `Text('…')`, `tooltip: '…'` and friends: text a user reads.
///
/// Interpolated strings are skipped — they carry runtime values and need a
/// parameterised ARB entry rather than a straight lookup, so flagging them
/// here would be noise rather than a finding.
final RegExp _hardcodedStrings = RegExp(
    r"(Text\(\s*|labelText:\s*|hintText:\s*|tooltip:\s*|label:\s*"
    r"|title:\s*|subtitle:\s*|message:\s*|description:\s*"
    r"|actionLabel:\s*|helperText:\s*|semanticLabel:\s*)"
    r"'([^'\\\\$]{2,120})'");

/// At least two letter-runs, i.e. actual words rather than a separator.
final RegExp _hasWords = RegExp(r'[A-Za-z]{2}');

/// Screens that deliberately draw edge to edge.
///
/// The splash is a full-bleed aurora with centred content — insetting it
/// would put a band of scaffold colour above the gradient, which is the
/// opposite of what it is for.
bool _exemptFromSafeArea(String path) => path.contains('splash_screen.dart');

/// Files with no BuildContext to look a string up with, or where the string
/// is not user-facing.
bool _exemptFromL10n(String path) =>
    path.contains('nav_config.dart') ||        // static tab config
    path.contains('pdf_export_service.dart') || // pdf package, not Flutter
    path.contains('/l10n/') ||
    // Const lists and top-level data built before any BuildContext exists.
    // These need restructuring into a function of AppLocalizations before
    // their strings can move, which is a change to the data shape rather
    // than a lookup swap.
    path.contains('note_template.dart') ||
    path.contains('suggested_prayers.dart') ||
    path.contains('app_tutorial_sequences.dart') ||
    path.contains('feature_intro.dart') ||
    // Android notification channels are created at startup, long before a
    // widget tree exists.
    path.contains('notification_service.dart') ||
    // Exception messages are developer-facing; UserFacingError is what turns
    // them into something a person reads, and that is already localised.
    path.contains('sync_api_client.dart') ||
    path.contains('http_sync_client.dart') ||
    path.contains('sync_endpoints.dart');

/// Whether `// l10n-exempt:` appears on the flagged line or the one above it.
///
/// For strings that genuinely cannot be looked up — OS notification channels
/// and const data built before any BuildContext exists. The marker must carry
/// a reason after the colon so the exemption is reviewable.
bool _suppressedAt(String src, int line) {
  final lines = src.split('\n');
  for (final i in [line - 1, line - 2]) {
    if (i >= 0 && i < lines.length && lines[i].contains('l10n-exempt:')) {
      return true;
    }
  }
  return false;
}

class _Finding {
  final String path;
  final int line;
  final String message;
  _Finding(this.path, this.line, this.message);
}

/// Whether a GestureDetector body already contains a widget that supplies its
/// own tap semantics. When it does, the detector is only driving a visual
/// effect (a press-scale animation, typically) and the real control underneath
/// is already reachable, so onTapUp without onTap is correct there — adding
/// onTap would fire the action twice.
bool _wrapsARealButton(String body) {
  const semanticControls = [
    'ElevatedButton(',
    'FilledButton(',
    'OutlinedButton(',
    'TextButton(',
    'IconButton(',
    'InkWell(',
    'CupertinoButton(',
  ];
  return semanticControls.any(body.contains);
}

class _Call {
  final int line;
  final String body;
  _Call(this.line, this.body);
}

/// Every `name(...)` call in [src], with its 1-based line and argument text.
///
/// Brackets are matched by depth so a nested widget tree stays inside its own
/// call. Comments and string literals are skipped: an apostrophe in a comment
/// ("the child's tap action") would otherwise open a phantom string and make
/// the matcher run past the closing bracket, silently swallowing the rest of
/// the file and turning every later check into a false negative.
Iterable<_Call> _callsTo(String name, String src) sync* {
  final pattern = RegExp('\\b$name\\(');
  for (final match in pattern.allMatches(src)) {
    // Skip a match that is itself inside a comment or string.
    if (_isInsideCommentOrString(src, match.start)) continue;

    var i = match.end;
    var depth = 1;
    String? quote;
    while (i < src.length && depth > 0) {
      final c = src[i];
      final next = i + 1 < src.length ? src[i + 1] : '';

      if (quote != null) {
        if (c == r'\') {
          i += 2;
          continue;
        }
        if (c == quote) quote = null;
        i++;
        continue;
      }
      if (c == '/' && next == '/') {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
        continue;
      }
      if (c == '/' && next == '*') {
        i += 2;
        while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
          i++;
        }
        i += 2;
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
      }
      i++;
    }
    if (depth != 0) continue; // unbalanced; skip rather than mis-report
    final line = '\n'.allMatches(src.substring(0, match.start)).length + 1;
    yield _Call(line, src.substring(match.end, i - 1));
  }
}

/// Whether [index] falls inside a line comment, block comment or string.
bool _isInsideCommentOrString(String src, int index) {
  var i = 0;
  String? quote;
  while (i < index) {
    final c = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';
    if (quote != null) {
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == '/' && next == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      if (i > index) return true;
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      if (i > index) return true;
      continue;
    }
    if (c == "'" || c == '"') quote = c;
    i++;
  }
  return quote != null;
}
