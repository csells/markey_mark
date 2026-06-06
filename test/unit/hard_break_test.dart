import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/attributes.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('Hard line breaks', () {
    test('two trailing spaces become a hard break run', () {
      final d = Markdown.parse('line one  \nline two');
      final node = d.nodes.first as TextBlockNode;
      expect(node.delta.toPlainText(), 'line one\nline two');
      expect(
        node.delta.runs.any((r) => r.attributes[InlineAttr.hardBreak] == true),
        isTrue,
      );
    });

    test('round-trips a hard break as two trailing spaces', () {
      const md = 'line one  \nline two';
      expect(Markdown.serialize(Markdown.parse(md)), md);
    });
  });
}
