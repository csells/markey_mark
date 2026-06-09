import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/attributes.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('Inline math', () {
    test('decodes \$...\$ to a run with the math attribute', () {
      final d = Markdown.parse(r'energy is $E = mc^2$ exactly');
      final para = d.nodes.first as TextBlockNode;
      final mathRun = para.delta.runs
          .firstWhere((r) => r.attributes[InlineAttr.math] == true);
      expect(mathRun.text, 'E = mc^2');
    });

    test('round-trips inline math', () {
      const md = r'energy is $E = mc^2$ exactly';
      expect(Markdown.serialize(Markdown.parse(md)), md);
    });

    test('does not consume block math', () {
      final d = Markdown.parse(r'$$' '\n' r'x^2' '\n' r'$$');
      expect(d.nodes.first, isA<MathBlockNode>());
    });
  });

  group('Block math', () {
    test('decodes \$\$...\$\$ to a MathBlockNode', () {
      final d = Markdown.parse(r'$$' '\n' r'x^2 + y^2' '\n' r'$$');
      final node = d.nodes.first as MathBlockNode;
      expect(node.tex, 'x^2 + y^2');
    });

    test('round-trips', () {
      const md = r'$$' '\n' r'a = b' '\n' r'$$';
      expect(Markdown.serialize(Markdown.parse(md)), md);
    });

    test('coexists with surrounding blocks', () {
      final d = Markdown.parse('text\n\n' r'$$' '\n' r'E=mc^2' '\n' r'$$' '\n\ntail');
      expect(d.nodes.whereType<MathBlockNode>().length, 1);
      expect(d.length, 3);
    });
  });
}
