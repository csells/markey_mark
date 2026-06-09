import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_state.dart';

void main() {
  group('parseStateDiagram', () {
    test('parses states and labeled transitions', () {
      final f = parseStateDiagram(
          'stateDiagram-v2\n[*] --> Idle\nIdle --> Running : start\n'
          'Running --> Idle : stop\nRunning --> [*]');
      expect(f, isNotNull);
      // Real states present.
      expect(f!.nodes.containsKey('Idle'), isTrue);
      expect(f.nodes.containsKey('Running'), isTrue);
      // [*] becomes pseudo start/end nodes.
      expect(f.nodes.length, greaterThanOrEqualTo(4));
      // Labeled transition preserved.
      final labeled =
          f.edges.firstWhere((e) => e.from == 'Idle' && e.to == 'Running');
      expect(labeled.label, 'start');
    });

    test('supports stateDiagram (non-v2)', () {
      final f = parseStateDiagram('stateDiagram\nA --> B');
      expect(f, isNotNull);
      expect(f!.edges.single.from, 'A');
      expect(f.edges.single.to, 'B');
    });

    test('returns null for non-state diagrams', () {
      expect(parseStateDiagram('graph TD\nA-->B'), isNull);
      expect(parseStateDiagram('pie\n"A":1'), isNull);
    });
  });
}
