import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  group('callouts (GitHub-style alerts)', () {
    test('decodes the marker into a callout kind, dropping the marker text', () {
      final doc = Markdown.parse('> [!NOTE]\n> Take note of this.');
      final nodes = doc.nodes.whereType<TextBlockNode>().toList();
      expect(nodes, isNotEmpty);
      expect(nodes.first.type, BlockType.quote);
      expect(nodes.first.callout, 'note');
      expect(nodes.first.delta.toPlainText(), 'Take note of this.');
    });

    test('recognizes all five kinds case-insensitively', () {
      for (final kind in ['NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION']) {
        final doc = Markdown.parse('> [!$kind]\n> body');
        final first = doc.nodes.whereType<TextBlockNode>().first;
        expect(first.callout, kind.toLowerCase());
      }
    });

    test('a plain blockquote has no callout', () {
      final doc = Markdown.parse('> just a quote');
      expect(doc.nodes.whereType<TextBlockNode>().first.callout, isNull);
    });

    test('marker on its own paragraph drops the empty marker block', () {
      final doc = Markdown.parse('> [!TIP]\n>\n> Helpful hint.');
      final quotes = doc.nodes
          .whereType<TextBlockNode>()
          .where((n) => n.type == BlockType.quote)
          .toList();
      expect(quotes.length, 1);
      expect(quotes.first.callout, 'tip');
      expect(quotes.first.delta.toPlainText(), 'Helpful hint.');
    });

    test('encodes a callout back to the [!KIND] marker form', () {
      final node = TextBlockNode.quote(
          delta: Delta.text('Body text'), callout: 'warning');
      final md = Markdown.serialize(Document([node]));
      expect(md, '> [!WARNING]\n> Body text');
    });

    test('round-trips through Markdown', () {
      const src = '> [!IMPORTANT]\n> Don\'t miss this.';
      final once = Markdown.parse(src);
      final out = Markdown.serialize(once);
      expect(out, src);
    });

    test('a multi-paragraph callout round-trips idempotently', () {
      const src = '> [!NOTE]\n> first\n>\n> second';
      final once = Markdown.serialize(Markdown.parse(src));
      final twice = Markdown.serialize(Markdown.parse(once));
      expect(twice, once);
      expect(once, src);
    });

    test('a callout followed by a plain quote stays separate', () {
      const src = '> [!TIP]\n> hint\n\n> just a quote';
      final twice =
          Markdown.serialize(Markdown.parse(Markdown.serialize(Markdown.parse(src))));
      expect(twice, src);
    });

    test('exports a callout to HTML with kind class', () {
      final node = TextBlockNode.quote(
          delta: Delta.text('Heads up'), callout: 'caution');
      final html = Markdown.toHtml(Document([node]));
      expect(html, contains('class="callout callout-caution"'));
      expect(html, contains('Heads up'));
    });
  });
}
