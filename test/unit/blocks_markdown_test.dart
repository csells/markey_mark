import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/document.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  TextBlockNode tb(Document d, int i) => d.nodes[i] as TextBlockNode;

  void expectStable(String md) {
    final once = Markdown.serialize(Markdown.parse(md));
    final twice = Markdown.serialize(Markdown.parse(once));
    expect(twice, once, reason: 'not idempotent: $md');
  }

  group('Bulleted lists', () {
    test('decodes each item to a bulleted_list_item', () {
      final d = Markdown.parse('- one\n- two');
      expect(d.length, 2);
      expect(tb(d, 0).type, BlockType.bulletedListItem);
      expect(tb(d, 0).delta.toPlainText(), 'one');
      expect(tb(d, 1).delta.toPlainText(), 'two');
    });

    test('round-trips tight', () {
      expect(Markdown.serialize(Markdown.parse('- one\n- two')), '- one\n- two');
      expectStable('- a\n- b\n- c');
    });

    test('preserves inline marks in items', () {
      final d = Markdown.parse('- has **bold**');
      expect(tb(d, 0).delta.isFormatted(4, 8, 'bold'), isTrue);
    });
  });

  group('Nested lists', () {
    test('decodes indentation levels', () {
      final d = Markdown.parse('- a\n  - b\n  - c\n- d');
      expect(d.length, 4);
      expect(tb(d, 0).delta.toPlainText(), 'a');
      expect(tb(d, 0).indent, 0);
      expect(tb(d, 1).delta.toPlainText(), 'b');
      expect(tb(d, 1).indent, 1);
      expect(tb(d, 2).indent, 1);
      expect(tb(d, 3).indent, 0);
    });

    test('round-trips nested lists', () {
      const md = '- a\n  - b\n  - c\n- d';
      expect(Markdown.serialize(Markdown.parse(md)), md);
    });
  });

  group('Numbered lists', () {
    test('decodes to numbered_list_item with numbers', () {
      final d = Markdown.parse('1. first\n2. second');
      expect(tb(d, 0).type, BlockType.numberedListItem);
      expect(tb(d, 0).attributes['number'], 1);
      expect(tb(d, 1).attributes['number'], 2);
    });

    test('round-trips', () {
      expect(Markdown.serialize(Markdown.parse('1. a\n2. b')), '1. a\n2. b');
    });
  });

  group('Task lists', () {
    test('decodes checkbox state', () {
      final d = Markdown.parse('- [ ] todo\n- [x] done');
      expect(tb(d, 0).type, BlockType.todoListItem);
      expect(tb(d, 0).checked, false);
      expect(tb(d, 0).delta.toPlainText(), 'todo');
      expect(tb(d, 1).checked, true);
      expect(tb(d, 1).delta.toPlainText(), 'done');
    });

    test('round-trips', () {
      expect(
        Markdown.serialize(Markdown.parse('- [ ] a\n- [x] b')),
        '- [ ] a\n- [x] b',
      );
    });
  });

  group('Block quotes', () {
    test('decodes to a quote block', () {
      final d = Markdown.parse('> quoted');
      expect(tb(d, 0).type, BlockType.quote);
      expect(tb(d, 0).delta.toPlainText(), 'quoted');
    });

    test('round-trips', () {
      expect(Markdown.serialize(Markdown.parse('> hello')), '> hello');
      expectStable('> a\n\nnormal');
    });
  });

  group('Fenced code blocks', () {
    test('decodes code + language', () {
      final d = Markdown.parse('```dart\nvar x = 1;\n```');
      final node = d.nodes.first as CodeBlockNode;
      expect(node.language, 'dart');
      expect(node.code, 'var x = 1;');
    });

    test('round-trips with language', () {
      const md = '```dart\nvar x = 1;\n```';
      expect(Markdown.serialize(Markdown.parse(md)), md);
    });

    test('code content is literal (not parsed as markdown)', () {
      final d = Markdown.parse('```\n**not bold**\n```');
      expect((d.nodes.first as CodeBlockNode).code, '**not bold**');
    });
  });

  group('Horizontal rule', () {
    test('decodes to a HorizontalRuleNode', () {
      final d = Markdown.parse('a\n\n---\n\nb');
      expect(d.nodes[1], isA<HorizontalRuleNode>());
    });

    test('round-trips as ---', () {
      expect(Markdown.serialize(Markdown.parse('---')), '---');
    });
  });

  group('Decoder structural branches', () {
    test('loose list items (with paragraph wrappers) decode correctly', () {
      final d = Markdown.parse('- one\n\n- two');
      expect(d.length, 2);
      expect(tb(d, 0).type, BlockType.bulletedListItem);
      expect(tb(d, 0).delta.toPlainText(), 'one');
    });

    test('multi-paragraph blockquote becomes multiple quote blocks', () {
      final d = Markdown.parse('> first\n>\n> second');
      final quotes = d.nodes.whereType<TextBlockNode>()
          .where((n) => n.type == BlockType.quote)
          .toList();
      expect(quotes.length, greaterThanOrEqualTo(2));
    });

    test('nested blockquote is flattened to quote blocks', () {
      final d = Markdown.parse('> outer\n>\n> > inner');
      expect(
        d.nodes.whereType<TextBlockNode>().every((n) =>
            n.type == BlockType.quote || n.type == BlockType.paragraph),
        isTrue,
      );
    });

    test('code block without a language', () {
      final d = Markdown.parse('```\nplain code\n```');
      final node = d.nodes.first as CodeBlockNode;
      expect(node.language, isNull);
      expect(node.code, 'plain code');
    });

    test('ordered list respecting a start number', () {
      final d = Markdown.parse('3. three\n4. four');
      expect(tb(d, 0).number, 3);
      expect(tb(d, 1).number, 4);
    });
  });

  group('Mixed document round-trip', () {
    test('idempotent + stable across a rich document', () {
      const md = '# Title\n\n'
          'A paragraph with **bold**.\n\n'
          '- one\n- two\n\n'
          '1. first\n2. second\n\n'
          '> a quote\n\n'
          '```dart\ncode();\n```\n\n'
          '---';
      expectStable(md);
    });
  });
}
