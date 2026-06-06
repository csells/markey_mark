import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
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
