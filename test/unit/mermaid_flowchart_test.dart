import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_flowchart.dart';

void main() {
  group('parseFlowchart', () {
    test('parses direction, nodes (shapes/labels) and edges', () {
      final f = parseFlowchart(
          'graph TD\nA[Start] --> B{Choice}\nB -->|yes| C[Do it]\nB --> D');
      expect(f, isNotNull);
      expect(f!.direction, FlowDirection.topDown);
      expect(f.nodes['A']!.label, 'Start');
      expect(f.nodes['A']!.shape, FlowShape.rect);
      expect(f.nodes['B']!.shape, FlowShape.diamond);
      expect(f.nodes['C']!.label, 'Do it');
      // 'D' had no label → label defaults to its id.
      expect(f.nodes['D']!.label, 'D');
      expect(f.edges.length, 3);
      expect(f.edges[0].from, 'A');
      expect(f.edges[0].to, 'B');
      expect(f.edges[1].label, 'yes');
    });

    test('supports flowchart keyword and LR direction', () {
      final f = parseFlowchart('flowchart LR\nA --> B')!;
      expect(f.direction, FlowDirection.leftRight);
    });

    test('assigns layered ranks (longest path from roots)', () {
      final f = parseFlowchart('graph TD\nA --> B\nB --> C\nA --> C')!;
      final ranks = f.ranks();
      expect(ranks['A'], 0);
      expect(ranks['B'], 1);
      expect(ranks['C'], 2); // longest path A->B->C
    });

    test('returns null for non-flowcharts', () {
      expect(parseFlowchart('pie\n"A":1'), isNull);
      expect(parseFlowchart('sequenceDiagram\nA->>B: x'), isNull);
    });

    test('returns null with no edges or nodes', () {
      expect(parseFlowchart('graph TD'), isNull);
    });
  });
}
