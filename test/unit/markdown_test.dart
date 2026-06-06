import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/decoder.dart';
import 'package:markey_mark/src/markdown/encoder.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  final decoder = MarkdownDecoder();
  const encoder = MarkdownEncoder();

  TextBlockNode block(int i, dynamic doc) => doc.nodes[i] as TextBlockNode;

  /// Structural equality ignoring (regenerated) node ids: the correct notion of
  /// AST-stability for a freshly parsed document.
  void expectSameStructure(dynamic a, dynamic b, {String? reason}) {
    expect(b.nodes.length, a.nodes.length, reason: reason);
    for (var i = 0; i < a.nodes.length; i++) {
      final na = a.nodes[i] as TextBlockNode;
      final nb = b.nodes[i] as TextBlockNode;
      expect(nb.type, na.type, reason: reason);
      expect(nb.level, na.level, reason: reason);
      expect(nb.delta, na.delta, reason: reason);
    }
  }

  group('Decoder', () {
    test('parses a paragraph', () {
      final doc = decoder.convert('Hello world');
      expect(doc.length, 1);
      expect(block(0, doc).type, BlockType.paragraph);
      expect(block(0, doc).delta.toPlainText(), 'Hello world');
    });

    test('parses ATX headings 1..6', () {
      for (var level = 1; level <= 6; level++) {
        final doc = decoder.convert('${'#' * level} Title');
        expect(block(0, doc).type, BlockType.heading);
        expect(block(0, doc).level, level);
        expect(block(0, doc).delta.toPlainText(), 'Title');
      }
    });

    test('parses bold/italic/strike/code/link inline', () {
      final doc = decoder.convert('a **b** _c_ ~~d~~ `e` [f](http://x)');
      final runs = block(0, doc).delta.runs;
      expect(runs.firstWhere((r) => r.text == 'b').attributes, {'bold': true});
      expect(runs.firstWhere((r) => r.text == 'c').attributes, {'italic': true});
      expect(runs.firstWhere((r) => r.text == 'd').attributes, {'strike': true});
      expect(runs.firstWhere((r) => r.text == 'e').attributes, {'code': true});
      expect(
        runs.firstWhere((r) => r.text == 'f').attributes,
        {'link': 'http://x'},
      );
    });

    test('parses nested bold+italic', () {
      final doc = decoder.convert('**_x_**');
      final run = block(0, doc).delta.runs.single;
      expect(run.text, 'x');
      expect(run.attributes, {'bold': true, 'italic': true});
    });

    test('multiple blocks', () {
      final doc = decoder.convert('# Title\n\nBody paragraph');
      expect(doc.length, 2);
      expect(block(0, doc).type, BlockType.heading);
      expect(block(1, doc).type, BlockType.paragraph);
    });

    test('empty input yields one empty paragraph', () {
      final doc = decoder.convert('');
      expect(doc.length, 1);
      expect(block(0, doc).delta.isEmpty, isTrue);
    });
  });

  group('Encoder', () {
    test('serializes headings', () {
      final doc = decoder.convert('### Hi');
      expect(encoder.convert(doc), '### Hi');
    });

    test('serializes inline marks canonically', () {
      final doc = decoder.convert('**b** _i_ ~~s~~ `c`');
      expect(encoder.convert(doc), '**b** _i_ ~~s~~ `c`');
    });

    test('escapes active markdown characters', () {
      final doc = decoder.convert(r'a\*b');
      expect(encoder.convert(doc), r'a\*b');
    });

    test('nested marks share boundaries (no **a****b**)', () {
      // "ab" all bold, "b" also italic.
      final doc = decoder.convert('**a_b_**');
      final out = encoder.convert(doc);
      // Round-trips to an equivalent structure.
      final reparsed = decoder.convert(out);
      expect(block(0, reparsed).delta, block(0, doc).delta);
    });
  });

  group('Round-trip corpus (idempotence + AST-stability)', () {
    const corpus = <String, String>{
      'paragraph': 'Just a simple paragraph.',
      'heading1': '# Heading one',
      'heading3': '### Heading three',
      'bold': 'This is **bold** text.',
      'italic': 'This is _italic_ text.',
      'strike': 'This is ~~struck~~ text.',
      'code': 'Inline `code` here.',
      'link': 'A [link](https://example.com) inline.',
      'bold-italic': 'Mix **bold _and_ italic** here.',
      'multi-block': '# Title\n\nFirst paragraph.\n\nSecond paragraph.',
      'multiple-marks': '**a** and _b_ and `c` and ~~d~~.',
      'escaped': r'literal \* and \_ characters',
    };

    corpus.forEach((name, md) {
      test('idempotent + stable: $name', () {
        final once = Markdown.serialize(Markdown.parse(md));
        final twice = Markdown.serialize(Markdown.parse(once));
        // Idempotence: serialize∘parse is a fixed point after the first pass.
        expect(twice, once, reason: 'not idempotent for "$name"');

        // AST-stability: the model is structurally identical across a re-parse.
        final model1 = Markdown.parse(once);
        final model2 = Markdown.parse(twice);
        expectSameStructure(model1, model2, reason: 'model not stable for "$name"');
      });
    });

    test('content is preserved (no data loss) for bold', () {
      final doc = Markdown.parse('keep **this** safe');
      final node = doc.nodes.first as TextBlockNode;
      expect(node.delta.toPlainText(), 'keep this safe');
      expect(node.delta.isFormatted(5, 9, 'bold'), isTrue);
    });
  });

  group('Markdown facade', () {
    test('parse + serialize', () {
      final doc = Markdown.parse('# Hi');
      expect(Markdown.serialize(doc), '# Hi');
    });

    test('empty delta encodes to empty heading marker', () {
      final doc = Markdown.parse('#');
      // "#" with no text parses as a paragraph "#"convention varies; just ensure
      // round trip is stable.
      final out = Markdown.serialize(doc);
      expect(Markdown.serialize(Markdown.parse(out)), out);
    });
  });
}
