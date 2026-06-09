import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Property-based fuzzing of the Markdown pipeline: for a large number of
/// randomly-generated documents, the canonical serialization must be
/// idempotent — `serialize(parse(serialize(parse(s)))) == serialize(parse(s))`.
///
/// This finds whole classes of round-trip bugs (separator handling, escaping,
/// block grouping) that example-based tests miss.
void main() {
  // Vocabulary seeded with block-marker-like and escapable special tokens so
  // the fuzzer probes escaping and re-parse ambiguity. (Raw HTML and the `==`
  // highlight delimiter as *literal* text are deliberately excluded — they are
  // known fidelity limitations tracked separately, not escaping bugs.)
  final words = [
    ...'the quick brown fox jumps over a lazy dog lorem ipsum'.split(' '),
    '#', '##', '-', '*', '+', '>', '1.', '~~', '`',
    r'a*b', 'a_b', 'c#d', r'$x$', r'back\slash',
  ];

  Delta randomDelta(Random r, {bool allowLinks = true}) {
    final runs = <TextRun>[];
    final n = 1 + r.nextInt(3);
    for (var i = 0; i < n; i++) {
      final word = words[r.nextInt(words.length)] +
          (i == 0 ? '' : ' ${words[r.nextInt(words.length)]}');
      final attrs = <String, Object?>{};
      // Mutually-exclusive-ish marks to keep things representable.
      final pick = r.nextInt(7);
      switch (pick) {
        case 0:
          attrs[InlineAttr.bold] = true;
        case 1:
          attrs[InlineAttr.italic] = true;
        case 2:
          attrs[InlineAttr.strike] = true;
        case 3:
          attrs[InlineAttr.highlight] = true;
        case 4:
          attrs[InlineAttr.code] = true;
        case 5:
          if (allowLinks) attrs[InlineAttr.link] = 'https://example.com/${r.nextInt(99)}';
      }
      runs.add(TextRun(i == 0 ? word : ' $word', attrs));
    }
    return Delta(runs);
  }

  Node randomBlock(Random r) {
    switch (r.nextInt(14)) {
      case 11:
        return TextBlockNode.definitionTerm(delta: randomDelta(r));
      case 12:
        return TextBlockNode.definitionDesc(delta: randomDelta(r));
      case 13:
        return TextBlockNode.footnoteDef(
            label: '${r.nextInt(50)}', delta: randomDelta(r, allowLinks: false));
      case 0:
        return TextBlockNode.paragraph(delta: randomDelta(r));
      case 1:
        return TextBlockNode.heading(level: 1 + r.nextInt(6), delta: randomDelta(r));
      case 2:
        return TextBlockNode.bullet(delta: randomDelta(r), indent: r.nextInt(3));
      case 3:
        return TextBlockNode.numbered(
            number: 1, delta: randomDelta(r), indent: r.nextInt(3));
      case 4:
        return TextBlockNode.todo(checked: r.nextBool(), delta: randomDelta(r));
      case 5:
        return TextBlockNode.quote(
          delta: randomDelta(r),
          callout: r.nextBool()
              ? ['note', 'tip', 'warning'][r.nextInt(3)]
              : null,
        );
      case 6:
        return CodeBlockNode(
            code: 'line1\nline2', language: r.nextBool() ? 'dart' : null);
      case 7:
        return HorizontalRuleNode();
      case 8:
        return ImageNode(
            url: 'https://img/${r.nextInt(9)}.png',
            alt: r.nextBool() ? 'alt text' : null);
      case 9:
        return MathBlockNode(tex: 'x^2 + y^2');
      default:
        return TableNode(
          rows: [
            [Delta.text('h1'), Delta.text('h2')],
            [randomDelta(r, allowLinks: false), randomDelta(r, allowLinks: false)],
          ],
          alignments: [TableAlign.left, TableAlign.right],
        );
    }
  }

  Document randomDocument(Random r) {
    final n = 1 + r.nextInt(6);
    return Document([for (var i = 0; i < n; i++) randomBlock(r)]);
  }

  test('canonical Markdown serialization is idempotent (fuzz)', () {
    final failures = <String>[];
    for (var seed = 0; seed < 500; seed++) {
      final r = Random(seed);
      final doc = randomDocument(r);
      final once = Markdown.serialize(doc);
      final twice = Markdown.serialize(Markdown.parse(once));
      final thrice = Markdown.serialize(Markdown.parse(twice));
      if (thrice != twice) {
        failures.add('seed=$seed\n--- once+parse (twice) ---\n$twice\n'
            '--- reparsed (thrice) ---\n$thrice\n');
      }
    }
    expect(failures, isEmpty,
        reason: 'non-idempotent round trips:\n${failures.take(5).join('\n')}');
  });

  test('HTML export never throws on random documents (fuzz)', () {
    for (var seed = 0; seed < 300; seed++) {
      final doc = randomDocument(Random(seed));
      expect(() => Markdown.toHtml(doc), returnsNormally, reason: 'seed=$seed');
    }
  });
}
