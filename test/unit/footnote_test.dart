import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/model/attributes.dart';
import 'package:markey_mark/src/model/node.dart';
import 'package:markey_mark/src/markdown/markdown.dart';

void main() {
  group('Footnotes', () {
    const md = 'Here is a note[^1].\n\n[^1]: The footnote text.';

    test('decodes an inline footnote reference as a run attribute', () {
      final d = Markdown.parse(md);
      final para = d.nodes.first as TextBlockNode;
      final ref = para.delta.runs
          .firstWhere((r) => r.attributes.containsKey(InlineAttr.footnote));
      expect(ref.attributes[InlineAttr.footnote], '1');
    });

    test('decodes the footnote definition as a FootnoteDefNode', () {
      final d = Markdown.parse(md);
      final def = d.nodes.whereType<TextBlockNode>()
          .firstWhere((n) => n.type == BlockType.footnoteDef);
      expect(def.footnoteLabel, '1');
      expect(def.delta.toPlainText().trim(), 'The footnote text.');
    });

    test('round-trips', () {
      final once = Markdown.serialize(Markdown.parse(md));
      final twice = Markdown.serialize(Markdown.parse(once));
      expect(twice, once);
      expect(once, contains('[^1]'));
      expect(once, contains('[^1]: The footnote text.'));
    });
  });
}
