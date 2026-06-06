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
