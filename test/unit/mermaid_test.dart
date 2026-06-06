import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('Mermaid markdown', () {
    test('a ```mermaid fence decodes to a MermaidNode', () {
      final d = Markdown.parse('```mermaid\ngraph TD;\nA-->B;\n```');
      final node = d.nodes.first as MermaidNode;
      expect(node.source, 'graph TD;\nA-->B;');
    });

    test('a normal code fence is NOT a MermaidNode', () {
      final d = Markdown.parse('```dart\nvar x = 1;\n```');
      expect(d.nodes.first, isA<CodeBlockNode>());
      expect(d.nodes.first, isNot(isA<MermaidNode>()));
    });

    test('round-trips as a mermaid fence', () {
      const md = '```mermaid\ngraph TD;\nA-->B;\n```';
      expect(Markdown.serialize(Markdown.parse(md)), md);
    });
  });
}
