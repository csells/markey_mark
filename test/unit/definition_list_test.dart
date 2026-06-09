import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('Definition lists', () {
    test('parses a term with definitions', () {
      final d = Markdown.parse('Apple\n: A fruit\n: A company');
      final term = d.nodes[0] as TextBlockNode;
      expect(term.type, BlockType.definitionTerm);
      expect(term.delta.toPlainText(), 'Apple');
      expect((d.nodes[1] as TextBlockNode).type, BlockType.definitionDesc);
      expect((d.nodes[1] as TextBlockNode).delta.toPlainText(), 'A fruit');
      expect((d.nodes[2] as TextBlockNode).delta.toPlainText(), 'A company');
    });

    test('round-trips', () {
      const md = 'Apple\n: A fruit\n: A company';
      expect(Markdown.serialize(Markdown.parse(md)), md);
    });

    test('preserves inline marks in definitions', () {
      final d = Markdown.parse('Term\n: has **bold**');
      expect((d.nodes[1] as TextBlockNode).delta.isFormatted(4, 8, 'bold'), isTrue);
    });

    test('a plain paragraph is not a definition list', () {
      final d = Markdown.parse('Just a paragraph.');
      expect(d.nodes.whereType<TextBlockNode>().first.type, BlockType.paragraph);
    });
  });
}
