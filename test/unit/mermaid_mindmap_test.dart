import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_mindmap.dart';

void main() {
  group('parseMindmap', () {
    const source = '''
mindmap
  root((mindmap))
    Origins
      Long history
    Research
      On effectiveness
''';

    test('parses the root node, stripping shape syntax', () {
      final m = parseMindmap(source);
      expect(m, isNotNull);
      expect(m!.root.text, 'mindmap');
    });

    test('builds the tree from indentation', () {
      final m = parseMindmap(source)!;
      expect(m.root.children.length, 2);
      expect(m.root.children[0].text, 'Origins');
      expect(m.root.children[0].children.single.text, 'Long history');
      expect(m.root.children[1].text, 'Research');
      expect(m.root.children[1].children.single.text, 'On effectiveness');
    });

    test('strips the common shape decorations', () {
      final m = parseMindmap('mindmap\n  r[Square]\n    c(Round)')!;
      expect(m.root.text, 'Square');
      expect(m.root.children.single.text, 'Round');
    });

    test('counts total nodes', () {
      expect(parseMindmap(source)!.nodeCount, 5);
    });

    test('returns null for non-mindmap diagrams', () {
      expect(parseMindmap('pie\n"A" : 1'), isNull);
      expect(parseMindmap('timeline\n2002 : LinkedIn'), isNull);
    });

    test('returns null when there is no root node', () {
      expect(parseMindmap('mindmap'), isNull);
    });
  });
}
