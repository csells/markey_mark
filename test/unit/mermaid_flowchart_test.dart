import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_flowchart.dart';

void main() {
  test('parses every node shape', () {
    final f = parseFlowchart(
        'graph TD\nA((circle)) --> B[[stadium]]\nC(rounded) --> D{diamond}\n'
        'E[box]\nF')!;
    expect(f.nodes['A']!.shape, FlowShape.circle);
    expect(f.nodes['B']!.shape, FlowShape.stadium);
    expect(f.nodes['C']!.shape, FlowShape.rounded);
    expect(f.nodes['D']!.shape, FlowShape.diamond);
    expect(f.nodes['E']!.shape, FlowShape.rect); // node-only line with label
    expect(f.nodes['F']!.shape, FlowShape.rect); // bare node-only line
  });

  testWidgets('FlowchartView paints every shape (LR)', (tester) async {
    final chart = parseFlowchart(
        'flowchart LR\nA((c)) --> B[[s]]\nC(r) --> D{d}\nE[box] --> F')!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 400,
            child: FlowchartView(
              chart: chart,
              textStyle: const TextStyle(fontSize: 12),
              lineColor: const Color(0xFF333333),
              fillColor: const Color(0xFFEEEEEE),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(FlowchartView), findsOneWidget);
  });

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
