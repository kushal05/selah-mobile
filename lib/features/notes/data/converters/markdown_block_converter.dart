import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../bible/domain/models/bible_reference.dart';
import '../../domain/models/block_type.dart';
import '../../domain/models/editor_block.dart';
import '../../domain/models/note_section.dart';
import '../../domain/models/note_table.dart';
import '../../domain/models/text_span_format.dart';

/// Converts between Markdown text and editor blocks.
///
/// [parse] turns a raw Markdown string (typically pasted from an external app)
/// into a list of [EditorBlock]s with inline formatting. [toMarkdown] does the
/// inverse for "Copy as Markdown".
///
/// The editor's block model is **single-line** (block `content` never contains
/// a newline) and its inline formatting is an offset-based, non-overlapping
/// span model ([buildFormattedTextSpan] resolves overlaps first-wins). This
/// converter therefore emits one block per source line and one merged
/// [TextSpanFormat] per run of identically-styled characters.
class MarkdownBlockConverter {
  static const _uuid = Uuid();

  // ==================== Parse (Markdown -> blocks) ====================

  /// Parse [markdown] into editor blocks. Each block's format offsets are
  /// relative to that block's own content (0-based). Every block is stamped
  /// with [section] and gets a fresh id.
  static List<EditorBlock> parse(
    String markdown, {
    NoteSection section = NoteSection.main,
  }) {
    final normalized = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final blocks = <EditorBlock>[];

    // Indent widths of the currently-open list levels; index == nesting level.
    // Nesting is relative to the enclosing item rather than a fixed number of
    // spaces, so both 2- and 4-space conventions nest one level per step.
    final indentStack = <int>[];

    var inFence = false;
    for (var idx = 0; idx < lines.length; idx++) {
      final line = lines[idx];

      // Fenced code block delimiters (``` or ~~~). Toggle state; drop the
      // fence line itself.
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        // Each fenced line becomes its own single-line code block (the model
        // has no multi-line block). Content is literal — no inline parsing.
        blocks.add(_block(BlockType.code, line, const [], section));
        continue;
      }

      // GFM table: a header row followed by a delimiter row (|---|:--:|).
      // Needs lookahead, so it is handled here rather than in _parseLine.
      if (idx + 1 < lines.length && _isTableStart(line, lines[idx + 1])) {
        final (tableBlock, consumed) = _parseTable(lines, idx, section);
        if (tableBlock != null) {
          indentStack.clear();
          blocks.add(tableBlock);
          idx += consumed - 1; // -1: the for-loop's idx++ consumes the last row
          continue;
        }
      }

      var block = _parseLine(line, section, indentStack);

      // Setext heading: a plain paragraph underlined by === or ---.
      if (block.type == BlockType.paragraph &&
          block.content.isNotEmpty &&
          idx + 1 < lines.length) {
        final next = lines[idx + 1].trim();
        if (RegExp(r'^=+$').hasMatch(next)) {
          block = block.copyWith(type: BlockType.heading1);
          idx++;
        } else if (RegExp(r'^-+$').hasMatch(next)) {
          block = block.copyWith(type: BlockType.heading2);
          idx++;
        }
      }

      // A non-empty, non-list block closes any open list. Blank lines don't —
      // they're legal between items of the same list.
      if (!block.type.isList && block.content.isNotEmpty) {
        indentStack.clear();
      }
      blocks.add(block);
    }

    if (blocks.isEmpty) {
      blocks.add(_block(BlockType.paragraph, '', const [], section));
    }
    return blocks;
  }

  // ==================== Tables (GFM) ====================

  /// A candidate table row: contains a pipe that isn't escaped or inside code.
  static bool _looksLikeTableRow(String line) {
    final t = line.trim();
    if (!t.contains('|')) return false;
    // Ignore a lone escaped pipe ("a \| b" is prose, not a table).
    return RegExp(r'(^|[^\\])\|').hasMatch(t);
  }

  /// The `|---|:--:|---:|` row that turns the preceding line into a header.
  static bool _isTableDelimiterRow(String line) {
    final cells = _splitTableRow(line);
    if (cells.isEmpty) return false;
    return cells.every((c) => RegExp(r'^:?-{1,}:?$').hasMatch(c.trim()));
  }

  /// Whether [header] + [delimiter] open a GFM table.
  ///
  /// GFM requires the delimiter row to have the SAME number of cells as the
  /// header; without that check ordinary prose followed by a rule or bullet
  /// ("cost | price" then "-") would be swallowed into a table.
  static bool _isTableStart(String header, String delimiter) {
    if (!_looksLikeTableRow(header)) return false;
    if (!_isTableDelimiterRow(delimiter)) return false;
    return _splitTableRow(header).length == _splitTableRow(delimiter).length;
  }

  /// Split a table row into raw cell strings, honouring `\|` escapes and
  /// dropping the optional leading/trailing pipes.
  static List<String> _splitTableRow(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|') && !t.endsWith(r'\|')) {
      t = t.substring(0, t.length - 1);
    }
    if (t.isEmpty) return const [];

    final cells = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      final ch = t[i];
      if (ch == r'\' && i + 1 < t.length && t[i + 1] == '|') {
        // Keep the escape so the inline parser emits a literal pipe.
        buf.write(r'\|');
        i++;
      } else if (ch == '|') {
        cells.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    cells.add(buf.toString());
    return cells;
  }

  static TableColumnAlign _alignFor(String delimiterCell) {
    final c = delimiterCell.trim();
    final left = c.startsWith(':');
    final right = c.endsWith(':');
    if (left && right) return TableColumnAlign.center;
    if (right) return TableColumnAlign.right;
    return TableColumnAlign.left;
  }

  /// Parse a table starting at [start] (header row). Returns the block and the
  /// number of source lines consumed.
  static (EditorBlock?, int) _parseTable(
    List<String> lines,
    int start,
    NoteSection section,
  ) {
    final header = _splitTableRow(lines[start]);
    if (header.isEmpty) return (null, 0);

    final alignments =
        _splitTableRow(lines[start + 1]).map(_alignFor).toList();

    final rows = <List<NoteTableCell>>[_cells(header)];
    var consumed = 2; // header + delimiter

    for (var i = start + 2; i < lines.length; i++) {
      if (!_looksLikeTableRow(lines[i])) break;
      rows.add(_cells(_splitTableRow(lines[i])));
      consumed++;
    }

    final table = NoteTable(rows: rows, alignments: alignments);
    return (
      _block(BlockType.table, jsonEncode(table.toJson()), const [], section),
      consumed,
    );
  }

  static List<NoteTableCell> _cells(List<String> raw) => raw.map((c) {
        final (text, formats) = _parseInline(c.trim());
        return NoteTableCell(text: text, formats: formats);
      }).toList();

  /// Resolve a list line's nesting level from its indent [width], maintaining
  /// [stack] (the indent width of each currently-open level).
  static int _levelFor(List<int> stack, int width) {
    while (stack.isNotEmpty && width < stack.last) {
      stack.removeLast();
    }
    if (stack.isEmpty) {
      stack.add(width);
      return 0;
    }
    if (width > stack.last) {
      stack.add(width);
    }
    return (stack.length - 1).clamp(0, 5);
  }

  /// Parse [text] as literal plain text — one paragraph per line, no markdown
  /// interpretation. Used by "Paste as plain text" so text containing markdown
  /// punctuation is inserted verbatim.
  static List<EditorBlock> parsePlain(
    String text, {
    NoteSection section = NoteSection.main,
  }) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized
        .split('\n')
        .map((line) => _block(BlockType.paragraph, line, const [], section))
        .toList();
  }

  /// Parse a single (non-fenced) line into a block. [indentStack] tracks open
  /// list levels and is mutated for list lines.
  static EditorBlock _parseLine(
    String line,
    NoteSection section,
    List<int> indentStack,
  ) {
    // Indent width in columns (a tab advances to the next 4-column stop).
    final leading = RegExp(r'^([ \t]*)').firstMatch(line)!.group(1)!;
    final width = leading.replaceAll('\t', '    ').length;
    final rest = line.substring(leading.length);

    // Heading (# .. ######, clamped to our 3 levels)
    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(rest);
    if (heading != null) {
      final level = heading.group(1)!.length.clamp(1, 3);
      final type = level == 1
          ? BlockType.heading1
          : level == 2
              ? BlockType.heading2
              : BlockType.heading3;
      // Strip an optional ATX closing sequence ("## Title ##"). It must be
      // preceded by whitespace, so "## C#" keeps its trailing hash.
      final body = heading.group(2)!.replaceFirst(RegExp(r'\s+#+\s*$'), '');
      final (text, formats) = _parseInline(body);
      return _block(type, text, formats, section);
    }

    // Blockquote
    final quote = RegExp(r'^>\s?(.*)$').firstMatch(rest);
    if (quote != null) {
      final (text, formats) = _parseInline(quote.group(1)!);
      return _block(BlockType.quote, text, formats, section);
    }

    // Checkbox: - [ ] / - [x]. The trailing text is optional so a bare
    // "- [ ]" is an empty task, but when present it must be space-separated
    // (so "- [x](url)" stays a bullet containing a link).
    final checkbox =
        RegExp(r'^[-*+]\s+\[([ xX])\](?:\s+(.*))?$').firstMatch(rest);
    if (checkbox != null) {
      final checked = checkbox.group(1)!.toLowerCase() == 'x';
      final (text, formats) = _parseInline(checkbox.group(2) ?? '');
      return _block(BlockType.checkbox, text, formats, section,
          indent: _levelFor(indentStack, width), isChecked: checked);
    }

    // Bullet list: -, *, +
    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(rest);
    if (bullet != null) {
      final (text, formats) = _parseInline(bullet.group(1)!);
      return _block(BlockType.bulletList, text, formats, section,
          indent: _levelFor(indentStack, width));
    }

    // Numbered list: 1. / 1)
    final numbered = RegExp(r'^\d+[.)]\s+(.*)$').firstMatch(rest);
    if (numbered != null) {
      final (text, formats) = _parseInline(numbered.group(1)!);
      return _block(BlockType.numberedList, text, formats, section,
          indent: _levelFor(indentStack, width));
    }

    // Horizontal rule -> rendered as an empty paragraph separator.
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(rest.trim())) {
      return _block(BlockType.paragraph, '', const [], section);
    }

    // Plain paragraph
    final (text, formats) = _parseInline(rest);
    return _block(BlockType.paragraph, text, formats, section);
  }

  static EditorBlock _block(
    BlockType type,
    String content,
    List<TextSpanFormat> formats,
    NoteSection section, {
    int indent = 0,
    bool? isChecked,
  }) {
    return EditorBlock(
      id: _uuid.v4(),
      type: type,
      content: content,
      formats: formats,
      // Only list items nest; headings/quotes/paragraphs sit at level 0.
      indentLevel: type.isList ? indent : 0,
      isChecked: type == BlockType.checkbox ? (isChecked ?? false) : null,
      section: section,
    );
  }

  // ==================== Inline parsing ====================

  /// Parse inline markdown into plain text + non-overlapping merged formats.
  static (String, List<TextSpanFormat>) _parseInline(String s) {
    final buf = StringBuffer();
    final styles = <_CharStyle>[];
    _walkInline(s, buf, styles, const _CharStyle());
    return (buf.toString(), _coalesce(styles));
  }

  /// Walk [s] applying [cur] to each emitted character, recursing into
  /// delimited spans. Characters are appended to [buf] and their combined
  /// style pushed to [styles] in lockstep.
  static void _walkInline(
    String s,
    StringBuffer buf,
    List<_CharStyle> styles,
    _CharStyle cur,
  ) {
    var i = 0;

    void emitLiteral(String text, _CharStyle style) {
      for (var k = 0; k < text.length; k++) {
        buf.write(text[k]);
        styles.add(style);
      }
    }

    while (i < s.length) {
      // Backslash escape: emit the escaped punctuation literally. Must come
      // first so `\*` can never open emphasis. (Escapes do not apply inside
      // code spans, which are emitted literally below.)
      if (s[i] == r'\' &&
          i + 1 < s.length &&
          _escapable.hasMatch(s[i + 1])) {
        buf.write(s[i + 1]);
        styles.add(cur);
        i += 2;
        continue;
      }

      // HTML entity (&amp; &#39; &#x27; ...) — markdown from web sources is
      // full of them. Decoded to the literal character; the result is never
      // re-parsed, so "&lt;u&gt;" stays visible text rather than underlining.
      final entity = _entityPattern.matchAsPrefix(s, i);
      if (entity != null) {
        final decoded = _decodeEntity(entity.group(0)!);
        if (decoded != null) {
          emitLiteral(decoded, cur);
          i = entity.end;
          continue;
        }
      }

      // Image: ![alt](url). There is no image block/span in the model, so keep
      // the alt text as plain text. Checked before links so the leading '!'
      // isn't left stranded and the image doesn't become a hyperlink.
      final image = RegExp(r'!\[([^\]]*)\]\(([^)]*)\)').matchAsPrefix(s, i);
      if (image != null) {
        _walkInline(image.group(1)!, buf, styles, cur);
        i = image.end;
        continue;
      }

      // Link: [text](url) — both text and URL must be non-empty.
      final link = RegExp(r'\[([^\]]*)\]\(([^)]*)\)').matchAsPrefix(s, i);
      if (link != null &&
          link.group(1)!.isNotEmpty &&
          link.group(2)!.isNotEmpty) {
        _walkInline(
            link.group(1)!, buf, styles, cur.copyWith(link: link.group(2)));
        i = link.end;
        continue;
      }

      // Inline code (literal, no nested parsing)
      if (s.startsWith('`', i)) {
        final close = s.indexOf('`', i + 1);
        if (close > i + 1) {
          emitLiteral(s.substring(i + 1, close), cur.copyWith(code: true));
          i = close + 1;
          continue;
        }
      }

      // Underline via <u>...</u>
      if (s.startsWith('<u>', i)) {
        final close = s.indexOf('</u>', i + 3);
        if (close != -1) {
          _walkInline(s.substring(i + 3, close), buf, styles,
              cur.copyWith(underline: true));
          i = close + 4;
          continue;
        }
      }

      // Bold+italic: *** or ___ (must precede the ** / * checks so the triple
      // run isn't consumed as bold, stranding a literal '*').
      final boldItalic = cur.copyWith(bold: true, italic: true);
      if (_tryPair(s, i, '***', boldItalic, buf, styles) ||
          _tryPair(s, i, '___', boldItalic, buf, styles)) {
        i = _lastConsumed;
        continue;
      }

      // Bold: ** or __
      if (_tryPair(s, i, '**', cur.copyWith(bold: true), buf, styles) ||
          _tryPair(s, i, '__', cur.copyWith(bold: true), buf, styles)) {
        i = _lastConsumed;
        continue;
      }

      // Strikethrough: ~~
      if (_tryPair(s, i, '~~', cur.copyWith(strike: true), buf, styles)) {
        i = _lastConsumed;
        continue;
      }

      // Italic: * or _
      if (_tryPair(s, i, '*', cur.copyWith(italic: true), buf, styles) ||
          _tryPair(s, i, '_', cur.copyWith(italic: true), buf, styles)) {
        i = _lastConsumed;
        continue;
      }

      // Plain character
      buf.write(s[i]);
      styles.add(cur);
      i++;
    }
  }

  static int _lastConsumed = 0;

  /// ASCII punctuation that may follow a backslash escape (CommonMark).
  static final _escapable = RegExp(r'''[!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~]''');

  /// Named or numeric HTML entity.
  static final _entityPattern =
      RegExp(r'&(#[xX][0-9A-Fa-f]+|#\d+|[A-Za-z][A-Za-z0-9]*);');

  static const _namedEntities = <String, String>{
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'copy': '©',
    'reg': '®',
    'trade': '™',
  };

  /// Decode a single entity, or null when it isn't one we recognise (in which
  /// case the caller leaves the raw text alone).
  static String? _decodeEntity(String raw) {
    final body = raw.substring(1, raw.length - 1); // strip '&' and ';'
    if (body.startsWith('#')) {
      final isHex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final code = isHex
          ? int.tryParse(body.substring(2), radix: 16)
          : int.tryParse(body.substring(1));
      // Reject out-of-range or surrogate code points — String.fromCharCode
      // would throw or produce mojibake.
      if (code == null || code < 0x20 || code > 0x10FFFF) return null;
      if (code >= 0xD800 && code <= 0xDFFF) return null;
      return String.fromCharCode(code);
    }
    return _namedEntities[body.toLowerCase()];
  }

  static bool _isWhitespace(String c) => c.trim().isEmpty;

  static bool _isAlphanumeric(String c) =>
      RegExp(r'[0-9A-Za-z]').hasMatch(c);

  /// Try to match [delim]...[delim] at [i]. On success recurse into the inner
  /// text with [inner] style, set [_lastConsumed] past the close, return true.
  ///
  /// Applies CommonMark's delimiter-flanking rules so ordinary prose and code
  /// aren't mangled: an opening run may not be followed by whitespace and a
  /// closing run may not be preceded by whitespace (so `2 * 3 * 4` stays
  /// literal), and `_` additionally may not open/close intraword (so
  /// `foo_bar_baz` and `snake_case` stay literal).
  static bool _tryPair(
    String s,
    int i,
    String delim,
    _CharStyle inner,
    StringBuffer buf,
    List<_CharStyle> styles,
  ) {
    if (!s.startsWith(delim, i)) return false;

    final contentStart = i + delim.length;
    if (contentStart >= s.length) return false;

    // Opening run must be left-flanking: not followed by whitespace.
    if (_isWhitespace(s[contentStart])) return false;
    // Underscore may not open inside a word.
    if (delim.startsWith('_') && i > 0 && _isAlphanumeric(s[i - 1])) {
      return false;
    }

    // Find a closing run that is right-flanking.
    var close = s.indexOf(delim, contentStart);
    while (close != -1) {
      final precededByWhitespace = _isWhitespace(s[close - 1]);
      final after = close + delim.length;
      final followedByAlnum =
          after < s.length && _isAlphanumeric(s[after]);
      final closesIntraword = delim.startsWith('_') && followedByAlnum;
      if (close > contentStart && !precededByWhitespace && !closesIntraword) {
        break;
      }
      close = s.indexOf(delim, close + delim.length);
    }
    if (close == -1) return false;

    _walkInline(s.substring(contentStart, close), buf, styles, inner);
    _lastConsumed = close + delim.length;
    return true;
  }

  /// Coalesce a per-character style list into non-overlapping formats.
  static List<TextSpanFormat> _coalesce(List<_CharStyle> styles) {
    final formats = <TextSpanFormat>[];
    var runStart = 0;
    for (var i = 1; i <= styles.length; i++) {
      final atEnd = i == styles.length;
      if (atEnd || styles[i] != styles[runStart]) {
        final style = styles[runStart];
        if (style.hasFormatting) {
          formats.add(style.toFormat(runStart, i));
        }
        runStart = i;
      }
    }
    return formats;
  }

  // ==================== Serialize (blocks -> Markdown) ====================

  /// Serialize [blocks] to a Markdown string.
  static String toMarkdown(List<EditorBlock> blocks) {
    final buf = StringBuffer();
    // Numbered-list counters keyed by indent level, so nested lists restart at
    // 1 rather than sharing one running sequence.
    final numberCounters = <int, int>{};
    var prevWasCode = false;

    for (final block in blocks) {
      // Close a fence when leaving a run of code blocks.
      if (prevWasCode && block.type != BlockType.code) {
        buf.writeln('```');
        prevWasCode = false;
      }

      if (block.type != BlockType.numberedList) {
        numberCounters.clear();
      } else {
        // Leaving a deeper level resets it, so a later nested run restarts.
        numberCounters.removeWhere((level, _) => level > block.indentLevel);
      }

      switch (block.type) {
        case BlockType.heading1:
          buf.writeln('# ${_inlineToMarkdown(block)}');
        case BlockType.heading2:
          buf.writeln('## ${_inlineToMarkdown(block)}');
        case BlockType.heading3:
          buf.writeln('### ${_inlineToMarkdown(block)}');
        case BlockType.paragraph:
          buf.writeln(_inlineToMarkdown(block));
        case BlockType.bulletList:
          buf.writeln('${_indent(block)}- ${_inlineToMarkdown(block)}');
        case BlockType.numberedList:
          final n = (numberCounters[block.indentLevel] ?? 0) + 1;
          numberCounters[block.indentLevel] = n;
          buf.writeln('${_indent(block)}$n. ${_inlineToMarkdown(block)}');
        case BlockType.checkbox:
          final mark = block.isChecked == true ? 'x' : ' ';
          buf.writeln('${_indent(block)}- [$mark] ${_inlineToMarkdown(block)}');
        case BlockType.quote:
          buf.writeln('> ${_inlineToMarkdown(block)}');
        case BlockType.code:
          if (!prevWasCode) buf.writeln('```');
          buf.writeln(block.content);
          prevWasCode = true;
        case BlockType.table:
          // `content` is JSON-encoded NoteTable — never emit it raw.
          buf.write(_tableToMarkdown(block));
        case BlockType.bibleReference:
          // `content` is JSON-encoded BibleReference — never emit it raw.
          final ref = BibleReference.tryParse(block.content);
          if (ref == null) {
            buf.writeln('> [Bible Reference]');
          } else {
            buf.writeln('> ${ref.displayReference}');
            if (ref.fullText.isNotEmpty) buf.writeln('> ${ref.fullText}');
          }
      }
    }
    if (prevWasCode) buf.writeln('```');

    return buf.toString().trimRight();
  }

  static String _indent(EditorBlock block) => '  ' * block.indentLevel;

  /// Serialize a [BlockType.table] block back to a GFM table.
  static String _tableToMarkdown(EditorBlock block) {
    final NoteTable table;
    try {
      table = NoteTable.fromJson(
          jsonDecode(block.content) as Map<String, dynamic>);
    } catch (_) {
      return '';
    }
    if (table.isEmpty) return '';

    final columns = table.columnCount;
    String renderRow(List<NoteTableCell> row) {
      final cells = List.generate(columns, (i) {
        if (i >= row.length) return '';
        // A literal pipe would otherwise split the cell on re-parse.
        return _cellToMarkdown(row[i]).replaceAll('|', r'\|');
      });
      return '| ${cells.join(' | ')} |';
    }

    final buf = StringBuffer();
    buf.writeln(renderRow(table.header));
    buf.writeln('| ${List.generate(columns, (i) => switch (table.alignAt(i)) {
          TableColumnAlign.left => '---',
          TableColumnAlign.center => ':---:',
          TableColumnAlign.right => '---:',
        }).join(' | ')} |');
    for (final row in table.body) {
      buf.writeln(renderRow(row));
    }
    return buf.toString();
  }

  /// Render one cell's text + formats as inline markdown, reusing the same
  /// transition-based emitter the block path uses.
  static String _cellToMarkdown(NoteTableCell cell) => _inlineToMarkdown(
        EditorBlock(
          id: '',
          type: BlockType.paragraph,
          content: cell.text,
          formats: cell.formats,
        ),
      );

  /// Render a block's content with its inline formats as Markdown markers.
  ///
  /// Markers are emitted at attribute *transitions* using a stack, so nested
  /// formatting nests properly (`**a _b_ c**`). Emitting open+close markers per
  /// styled run instead would collide adjacent runs into `****`, which reparses
  /// as literal asterisks.
  static String _inlineToMarkdown(EditorBlock block) {
    final content = block.content;
    if (content.isEmpty) return '';

    // Per-character merged style map from the (possibly overlapping) formats.
    final styles = List<_CharStyle>.filled(content.length, const _CharStyle());
    for (final f in block.formats) {
      final start = f.start.clamp(0, content.length);
      final end = f.end.clamp(0, content.length);
      for (var i = start; i < end; i++) {
        styles[i] = styles[i].merge(f);
      }
    }

    // Only escape when the literal text would itself parse as markdown —
    // otherwise ordinary prose and URLs would be needlessly littered with
    // backslashes (`foo_bar_baz` is already literal thanks to flanking rules).
    final (reparsed, reformats) = _parseInline(content);
    final needsEscape = reparsed != content || reformats.isNotEmpty;

    final out = StringBuffer();
    final open = <String>[]; // attribute keys, outermost first

    for (var i = 0; i <= content.length; i++) {
      final want = i < content.length ? _attrsOf(styles[i]) : const <String>[];

      // Close from the top down to the first attribute that is no longer
      // wanted; anything above it that is still wanted gets reopened below.
      var cut = open.length;
      for (var k = 0; k < open.length; k++) {
        if (!want.contains(open[k])) {
          cut = k;
          break;
        }
      }
      for (var k = open.length - 1; k >= cut; k--) {
        out.write(_closeMarker(open[k]));
      }
      open.removeRange(cut, open.length);

      for (final attr in want) {
        if (!open.contains(attr)) {
          out.write(_openMarker(attr));
          open.add(attr);
        }
      }

      if (i < content.length) {
        final ch = content[i];
        // Text inside a code span is already literal — never escape it.
        final inCode = open.contains('code');
        out.write(!needsEscape || inCode ? ch : _escapeChar(ch));
      }
    }
    return out.toString();
  }

  /// Active attributes of [s] in canonical nesting order (outermost first).
  static List<String> _attrsOf(_CharStyle s) => [
        if (s.link != null && s.link!.isNotEmpty) 'link:${s.link}',
        if (s.bold) 'bold',
        if (s.italic) 'italic',
        if (s.strike) 'strike',
        if (s.underline) 'underline',
        if (s.code) 'code',
      ];

  static String _openMarker(String attr) {
    if (attr.startsWith('link:')) return '[';
    return switch (attr) {
      'bold' => '**',
      'italic' => '_',
      'strike' => '~~',
      'underline' => '<u>',
      'code' => '`',
      _ => '',
    };
  }

  static String _closeMarker(String attr) {
    if (attr.startsWith('link:')) return '](${attr.substring(5)})';
    return switch (attr) {
      'bold' => '**',
      'italic' => '_',
      'strike' => '~~',
      'underline' => '</u>',
      'code' => '`',
      _ => '',
    };
  }

  // '&' is included because entities are decoded on parse: without escaping it,
  // content literally containing "&amp;" would decode to "&" on a re-parse.
  static final _needsEscaping = RegExp(r'[\\`*_~\[\]<>&]');

  static String _escapeChar(String ch) =>
      _needsEscaping.hasMatch(ch) ? '\\$ch' : ch;
}

/// Immutable per-character style used while (de)coalescing inline formatting.
class _CharStyle {
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;
  final String? link;

  const _CharStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.link,
  });

  // Mirrors TextSpanFormat.hasFormatting — an empty link URL is not formatting.
  bool get hasFormatting =>
      bold ||
      italic ||
      underline ||
      strike ||
      code ||
      (link != null && link!.isNotEmpty);

  _CharStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? code,
    String? link,
  }) {
    return _CharStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strike: strike ?? this.strike,
      code: code ?? this.code,
      link: link ?? this.link,
    );
  }

  /// Merge the boolean/link attributes of [f] onto this style (OR semantics).
  _CharStyle merge(TextSpanFormat f) {
    return _CharStyle(
      bold: bold || f.isBold,
      italic: italic || f.isItalic,
      underline: underline || f.isUnderline,
      strike: strike || f.isStrikethrough,
      code: code || f.isCode,
      link: f.link ?? link,
    );
  }

  TextSpanFormat toFormat(int start, int end) {
    return TextSpanFormat(
      start: start,
      end: end,
      isBold: bold,
      isItalic: italic,
      isUnderline: underline,
      isStrikethrough: strike,
      isCode: code,
      link: link,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _CharStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.code == code &&
      other.link == link;

  @override
  int get hashCode => Object.hash(bold, italic, underline, strike, code, link);
}
