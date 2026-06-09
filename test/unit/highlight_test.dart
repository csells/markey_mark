import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  group('highlight (==mark==) inline formatting', () {
    test('decodes ==text== into a highlight run', () {
      final doc = Markdown.parse('a ==hot== b');
      final delta = (doc.nodes.first as TextBlockNode).delta;
      final runs = delta.runs;
      final marked =
          runs.firstWhere((r) => r.attributes[InlineAttr.highlight] == true);
      expect(marked.text, 'hot');
    });

    test('encodes a highlight run back to ==text==', () {
      final delta = Delta.empty()
          .insert(0, 'a ')
          .insert(2, 'hot', const {InlineAttr.highlight: true})
          .insert(5, ' b');
      expect(Markdown.deltaToInline(delta), 'a ==hot== b');
    });

    test('round-trips through Markdown', () {
      const src = 'see ==this== now';
      expect(Markdown.serialize(Markdown.parse(src)), src);
    });

    test('nests with other marks', () {
      final doc = Markdown.parse('==**bold hot**==');
      final delta = (doc.nodes.first as TextBlockNode).delta;
      final run = delta.runs.first;
      expect(run.attributes[InlineAttr.highlight], true);
      expect(run.attributes[InlineAttr.bold], true);
    });

    test('exports to HTML as <mark>', () {
      expect('==hi=='.markdownToHtml(), '<p><mark>hi</mark></p>');
    });
  });
}
