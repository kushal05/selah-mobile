import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/features/notes/data/converters/markdown_block_converter.dart';
import 'package:notify/features/notes/domain/models/block_type.dart';
import 'package:notify/features/notes/domain/models/editor_block.dart';
import 'package:notify/features/notes/domain/models/note_table.dart';
import 'package:notify/features/notes/domain/models/text_span_format.dart';

void main() {
  group('MarkdownBlockConverter.parse — block types', () {
    test('headings', () {
      final blocks = MarkdownBlockConverter.parse('# H1\n## H2\n### H3');
      expect(blocks.map((b) => b.type).toList(), [
        BlockType.heading1,
        BlockType.heading2,
        BlockType.heading3,
      ]);
      expect(blocks[0].content, 'H1');
      expect(blocks[2].content, 'H3');
    });

    test('bullet, numbered, checkbox, quote', () {
      final blocks = MarkdownBlockConverter.parse(
          '- a\n1. b\n- [ ] c\n- [x] d\n> quoted');
      expect(blocks[0].type, BlockType.bulletList);
      expect(blocks[1].type, BlockType.numberedList);
      expect(blocks[2].type, BlockType.checkbox);
      expect(blocks[2].isChecked, false);
      expect(blocks[3].type, BlockType.checkbox);
      expect(blocks[3].isChecked, true);
      expect(blocks[4].type, BlockType.quote);
      expect(blocks[4].content, 'quoted');
    });

    test('indentation maps to indentLevel', () {
      final blocks = MarkdownBlockConverter.parse('- a\n  - b\n    - c');
      expect(blocks[0].indentLevel, 0);
      expect(blocks[1].indentLevel, 1);
      expect(blocks[2].indentLevel, 2);
    });

    test('fenced code block -> one code block per line', () {
      final blocks = MarkdownBlockConverter.parse('```\nline1\nline2\n```');
      expect(blocks.every((b) => b.type == BlockType.code), true);
      expect(blocks.map((b) => b.content).toList(), ['line1', 'line2']);
    });
  });

  group('MarkdownBlockConverter.parse — inline formats', () {
    TextSpanFormat fmtAt(EditorBlock b, int i) =>
        b.formats.firstWhere((f) => i >= f.start && i < f.end);

    test('bold offsets exclude delimiters', () {
      final b = MarkdownBlockConverter.parse('a **bold** c').first;
      expect(b.content, 'a bold c');
      final f = fmtAt(b, 2); // 'b' of bold
      expect(f.isBold, true);
      expect(b.content.substring(f.start, f.end), 'bold');
    });

    test('italic, strikethrough, inline code', () {
      final b = MarkdownBlockConverter.parse('_i_ ~~s~~ `k`').first;
      expect(b.content, 'i s k');
      expect(b.formats.any((f) => f.isItalic), true);
      expect(b.formats.any((f) => f.isStrikethrough), true);
      expect(b.formats.any((f) => f.isCode), true);
    });

    test('nested bold+italic merges into one span (non-overlapping)', () {
      final b = MarkdownBlockConverter.parse('**a _b_ c**').first;
      expect(b.content, 'a b c');
      // The 'b' character must carry BOTH bold and italic in a single span.
      final f = fmtAt(b, 2);
      expect(f.isBold, true);
      expect(f.isItalic, true);
      // No two formats may overlap.
      for (var i = 0; i < b.formats.length; i++) {
        for (var j = i + 1; j < b.formats.length; j++) {
          final a = b.formats[i], c = b.formats[j];
          expect(a.start < c.end && c.start < a.end, false,
              reason: 'formats overlap: $a vs $c');
        }
      }
    });

    test('link captures text and url', () {
      final b = MarkdownBlockConverter.parse('see [docs](https://x.io) now').first;
      expect(b.content, 'see docs now');
      final linkFmt = b.formats.firstWhere((f) => f.link != null);
      expect(b.content.substring(linkFmt.start, linkFmt.end), 'docs');
      expect(linkFmt.link, 'https://x.io');
    });
  });

  group('MarkdownBlockConverter — plain text is not mangled', () {
    test('snake_case / intraword underscores stay literal', () {
      final b = MarkdownBlockConverter.parse('call foo_bar_baz now').first;
      expect(b.content, 'call foo_bar_baz now');
      expect(b.formats, isEmpty);
    });

    test('asterisks surrounded by spaces stay literal', () {
      final b = MarkdownBlockConverter.parse('area = 2 * 3 * 4').first;
      expect(b.content, 'area = 2 * 3 * 4');
      expect(b.formats, isEmpty);
    });

    test('url with underscores survives', () {
      final b =
          MarkdownBlockConverter.parse('https://x.com/a_b_c/d_e_f').first;
      expect(b.content, 'https://x.com/a_b_c/d_e_f');
      expect(b.formats, isEmpty);
    });

    test('real emphasis still parses after flanking rules', () {
      final b = MarkdownBlockConverter.parse('_yes_ and **no**').first;
      expect(b.content, 'yes and no');
      expect(b.formats.any((f) => f.isItalic), true);
      expect(b.formats.any((f) => f.isBold), true);
    });

    test('empty link url is left literal', () {
      final b = MarkdownBlockConverter.parse('see [text]() here').first;
      expect(b.formats.any((f) => f.link != null), false);
    });

    test('parsePlain inserts markdown verbatim, one paragraph per line', () {
      final blocks = MarkdownBlockConverter.parsePlain('# not a heading\n- *x*');
      expect(blocks.length, 2);
      expect(blocks[0].type, BlockType.paragraph);
      expect(blocks[0].content, '# not a heading');
      expect(blocks[1].content, '- *x*');
      expect(blocks.every((b) => b.formats.isEmpty), true);
    });
  });

  group('MarkdownBlockConverter — CommonMark coverage', () {
    test('nesting is relative: 2-space and 4-space both nest one level', () {
      for (final src in ['- a\n  - b\n- c', '- a\n    - b\n- c']) {
        final blocks = MarkdownBlockConverter.parse(src);
        expect(blocks.map((b) => b.indentLevel).toList(), [0, 1, 0],
            reason: 'for: $src');
      }
    });

    test('deeper nesting increments one level per step', () {
      final blocks =
          MarkdownBlockConverter.parse('- a\n    - b\n        - c\n- d');
      expect(blocks.map((b) => b.indentLevel).toList(), [0, 1, 2, 0]);
    });

    test('blank line between items does not reset nesting', () {
      final blocks = MarkdownBlockConverter.parse('- a\n\n  - b');
      expect(blocks.last.indentLevel, 1);
    });

    test('*** and ___ produce bold+italic with no stray delimiters', () {
      for (final src in ['***both***', '___both___']) {
        final b = MarkdownBlockConverter.parse(src).first;
        expect(b.content, 'both', reason: 'for: $src');
        expect(b.formats.single.isBold, true);
        expect(b.formats.single.isItalic, true);
      }
    });

    test('images degrade to alt text — no stray "!" and not a link', () {
      final b = MarkdownBlockConverter.parse('![alt](http://x/y.png)').first;
      expect(b.content, 'alt');
      expect(b.formats.any((f) => f.link != null), false);
    });

    test('backslash escapes are literal and suppress emphasis', () {
      final b = MarkdownBlockConverter.parse(r'literal \*not italic\*').first;
      expect(b.content, 'literal *not italic*');
      expect(b.formats, isEmpty);
    });

    test('ATX closing sequence stripped, but "C#" preserved', () {
      expect(MarkdownBlockConverter.parse('## Title ##').first.content, 'Title');
      expect(MarkdownBlockConverter.parse('## C#').first.content, 'C#');
    });

    test('bare "- [ ]" is an empty task, not a bullet', () {
      final empty = MarkdownBlockConverter.parse('- [ ]').first;
      expect(empty.type, BlockType.checkbox);
      expect(empty.content, '');
      expect(empty.isChecked, false);

      final checked = MarkdownBlockConverter.parse('- [x]').first;
      expect(checked.type, BlockType.checkbox);
      expect(checked.isChecked, true);

      // Trailing text must be space-separated: "- [x](url)" is a link bullet.
      final link = MarkdownBlockConverter.parse('- [x](http://u)').first;
      expect(link.type, BlockType.bulletList);
      expect(link.formats.any((f) => f.link == 'http://u'), true);
    });

    test('setext headings', () {
      final h1 = MarkdownBlockConverter.parse('Title\n=====').first;
      expect(h1.type, BlockType.heading1);
      expect(h1.content, 'Title');

      final h2 = MarkdownBlockConverter.parse('Sub\n---').first;
      expect(h2.type, BlockType.heading2);
      expect(h2.content, 'Sub');

      // A standalone rule is not a setext underline.
      final rule = MarkdownBlockConverter.parse('- a\n---');
      expect(rule.first.type, BlockType.bulletList);
    });
  });

  group('MarkdownBlockConverter — nested numbering', () {
    test('nested numbered lists restart per indent level', () {
      final md = MarkdownBlockConverter.parse('1. a\n2. b\n  1. b1\n  2. b2\n3. c');
      final out = MarkdownBlockConverter.toMarkdown(md);
      expect(out, '1. a\n2. b\n  1. b1\n  2. b2\n3. c');
    });
  });

  group('MarkdownBlockConverter — HTML entities', () {
    test('named, numeric and hex entities decode', () {
      expect(MarkdownBlockConverter.parse('A &amp; B').first.content, 'A & B');
      expect(MarkdownBlockConverter.parse('it&#39;s').first.content, "it's");
      expect(MarkdownBlockConverter.parse('x &#x27; y').first.content, "x ' y");
    });

    test('decoded entities are not re-parsed as markup', () {
      final b = MarkdownBlockConverter.parse('&lt;u&gt;x&lt;/u&gt;').first;
      expect(b.content, '<u>x</u>');
      expect(b.formats.any((f) => f.isUnderline), false);
    });

    test('unknown and out-of-range entities are left literal', () {
      expect(MarkdownBlockConverter.parse('a &bogus; b').first.content,
          'a &bogus; b');
      expect(MarkdownBlockConverter.parse('x &#999999999; y').first.content,
          'x &#999999999; y');
      expect(
          MarkdownBlockConverter.parse('Tom & Jerry').first.content, 'Tom & Jerry');
    });
  });

  group('MarkdownBlockConverter — tables', () {
    NoteTable tableOf(String md) {
      final block = MarkdownBlockConverter.parse(md).first;
      expect(block.type, BlockType.table);
      return NoteTable.fromJson(
          jsonDecode(block.content) as Map<String, dynamic>);
    }

    test('parses header, delimiter and body rows', () {
      final t = tableOf('| a | b |\n|---|---|\n| 1 | 2 |');
      expect(t.columnCount, 2);
      expect(t.header.map((c) => c.text).toList(), ['a', 'b']);
      expect(t.body.single.map((c) => c.text).toList(), ['1', '2']);
    });

    test('column alignment from the delimiter row', () {
      final t = tableOf('| L | C | R |\n|:--|:-:|--:|\n| 1 | 2 | 3 |');
      expect(t.alignAt(0), TableColumnAlign.left);
      expect(t.alignAt(1), TableColumnAlign.center);
      expect(t.alignAt(2), TableColumnAlign.right);
    });

    test('cells keep inline formatting', () {
      final t = tableOf('| **a** | `b` |\n|---|---|\n| [x](http://u) | ~~y~~ |');
      expect(t.header[0].text, 'a');
      expect(t.header[0].formats.single.isBold, true);
      expect(t.header[1].formats.single.isCode, true);
      expect(t.body[0][0].formats.single.link, 'http://u');
      expect(t.body[0][1].formats.single.isStrikethrough, true);
    });

    test('works without outer pipes', () {
      final t = tableOf('a | b\n--- | ---\n1 | 2');
      expect(t.header.map((c) => c.text).toList(), ['a', 'b']);
    });

    test('escaped pipe stays inside the cell', () {
      final t = tableOf('| a \\| b | c |\n|---|---|\n| 1 | 2 |');
      expect(t.header[0].text, 'a | b');
      expect(t.columnCount, 2);
    });

    test('ragged rows do not throw and pad on render', () {
      final t = tableOf('| a | b | c |\n|---|---|---|\n| 1 |');
      expect(t.columnCount, 3);
      expect(t.body.single.length, 1);
    });

    test('prose containing a pipe is NOT a table', () {
      final blocks = MarkdownBlockConverter.parse('a | b just prose');
      expect(blocks.single.type, BlockType.paragraph);
    });

    test('delimiter row must match the header cell count (GFM)', () {
      // 2 header cells vs 1 delimiter cell -> not a table.
      final mismatch = MarkdownBlockConverter.parse('| a | b |\n|---|');
      expect(mismatch.every((b) => b.type != BlockType.table), true);

      // Prose + a rule must not be swallowed into a table.
      final prose = MarkdownBlockConverter.parse('cost | price\n-');
      expect(prose.every((b) => b.type != BlockType.table), true);

      // Matching counts still parse.
      expect(MarkdownBlockConverter.parse('a|b\n---|---').first.type,
          BlockType.table);
    });

    test('table followed by a paragraph', () {
      final blocks = MarkdownBlockConverter.parse('| a |\n|---|\n| 1 |\nafter');
      expect(blocks.map((b) => b.type).toList(),
          [BlockType.table, BlockType.paragraph]);
      expect(blocks.last.content, 'after');
    });

    test('exact GFM round-trip', () {
      const src = '| L | C | R |\n|:--|:-:|--:|\n| **1** | 2 | [x](http://u) |';
      final once = MarkdownBlockConverter.toMarkdown(
          MarkdownBlockConverter.parse(src));
      final twice = MarkdownBlockConverter.toMarkdown(
          MarkdownBlockConverter.parse(once));
      expect(twice, once);
      expect(once, contains(':---:'));
      expect(once, contains('---:'));
    });

    test('table export never leaks raw JSON', () {
      final blocks = MarkdownBlockConverter.parse('| a | b |\n|---|---|\n| 1 | 2 |');
      final md = MarkdownBlockConverter.toMarkdown(blocks);
      expect(md, isNot(contains('"rows"')));
      expect(md, isNot(contains('alignments')));
      expect(md, contains('| a | b |'));
    });

    test('malformed table JSON degrades to empty, never throws', () {
      const block = EditorBlock(
          id: 'x', type: BlockType.table, content: 'not json');
      expect(MarkdownBlockConverter.toMarkdown([block]), '');
    });
  });

  group('MarkdownBlockConverter — export safety', () {
    test('bible reference exports as a readable reference, never raw JSON', () {
      final block = EditorBlock.bibleReference(
        book: 'John',
        chapter: 3,
        verses: const [16],
        version: 'ESV',
        verseTexts: const [],
      );
      final md = MarkdownBlockConverter.toMarkdown([block]);

      expect(md, contains('John'));
      // The block's `content` is JSON — none of it may leak into the output.
      expect(md, isNot(contains('{')));
      expect(md, isNot(contains('"reference"')));
      expect(md, isNot(contains('insertedAt')));
    });

    test('malformed bible reference degrades to a placeholder', () {
      const block = EditorBlock(
        id: 'x',
        type: BlockType.bibleReference,
        content: 'not json',
      );
      expect(MarkdownBlockConverter.toMarkdown([block]),
          contains('[Bible Reference]'));
    });
  });

  group('MarkdownBlockConverter round-trip', () {
    /// Exact signature of a block list: type, indent, content and every format
    /// range. Anything less strict hides corruption like `**a ****_b_**** c**`.
    String sig(List<EditorBlock> blocks) => blocks
        .map((b) => '${b.type.name}(${b.indentLevel}):"${b.content}"'
            '${b.formats.map((f) => '[${f.start},${f.end})'
                '${f.isBold ? 'B' : ''}${f.isItalic ? 'I' : ''}'
                '${f.isCode ? 'C' : ''}${f.isStrikethrough ? 'S' : ''}'
                '${f.isUnderline ? 'U' : ''}${f.link ?? ''}').join()}')
        .join(' | ');

    void expectExactRoundTrip(String source) {
      final parsed = MarkdownBlockConverter.parse(source);
      final md = MarkdownBlockConverter.toMarkdown(parsed);
      final reparsed = MarkdownBlockConverter.parse(md);
      expect(sig(reparsed), sig(parsed),
          reason: 'round-trip changed\nsource: $source\nmarkdown: $md');
    }

    final cases = <String, String>{
      'bold': 'a **b** c',
      'nested bold+italic': '**a _b_ c**',
      'triple emphasis': '***x***',
      'code span': 'run `npm i` now',
      'code inside bold': '**b `c` d**',
      'strikethrough': '~~gone~~',
      'link': 'see [docs](http://x.io)',
      'link with bold': 'see [**d**](http://x.io)',
      'underline': 'a <u>u</u> b',
      'all combined': '***~~<u>x</u>~~***',
      'nested bullets': '- a\n  - b\n    - c',
      'nested numbers': '1. a\n  1. b\n2. c',
      'tasks': '- [x] done **b**\n- [ ] todo',
      'heading with bold': '## H2 with **bold**',
      'quote': '> quoted **b**',
      'code fence': '```\nline1\nline2\n```',
      'escaped asterisks stay literal': r'a \*literal\* b',
      'escaped backticks stay literal': r'a \`x\` b',
      'snake_case': 'foo_bar_baz',
      'math asterisks': '2 * 3 * 4',
      'url with underscores': 'https://x.com/a_b_c',
      'literal mixed with real formatting': r'\*lit\* and **bold**',
      'entity stays literal after decode': 'A &amp; B',
      'bare ampersand': 'Tom & Jerry',
      'entity inside bold': '**A &amp; B**',
    };

    cases.forEach((name, source) {
      test('exact round-trip: $name', () => expectExactRoundTrip(source));
    });
  });
}
