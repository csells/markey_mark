import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('Front matter', () {
    const md = '---\ntitle: Hello\ntags: [a, b]\n---\n\nBody paragraph.';

    test('extracts leading YAML front matter into a node', () {
      final d = Markdown.parse(md);
      final fm = d.nodes.first as FrontMatterNode;
      expect(fm.yaml, 'title: Hello\ntags: [a, b]');
      expect((d.nodes[1] as TextBlockNode).delta.toPlainText(), 'Body paragraph.');
    });

    test('round-trips', () {
      final once = Markdown.serialize(Markdown.parse(md));
      expect(once, md);
      expect(Markdown.serialize(Markdown.parse(once)), once);
    });

    test('--- not at the very start is a horizontal rule, not front matter', () {
      final d = Markdown.parse('intro\n\n---\n\nmore');
      expect(d.nodes.whereType<FrontMatterNode>(), isEmpty);
      expect(d.nodes.whereType<HorizontalRuleNode>().length, 1);
    });
  });
}
