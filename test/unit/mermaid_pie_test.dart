import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_pie.dart';

void main() {
  group('parsePie', () {
    test('parses title and slices', () {
      final pie = parsePie('pie title Pets\n"Dogs" : 386\n"Cats" : 85\n"Rats" : 15');
      expect(pie, isNotNull);
      expect(pie!.title, 'Pets');
      expect(pie.slices.length, 3);
      expect(pie.slices[0].label, 'Dogs');
      expect(pie.slices[0].value, 386);
      expect(pie.slices[2].label, 'Rats');
    });

    test('parses without a title and tolerates showData', () {
      final pie = parsePie('pie showData\n"A" : 1\n"B" : 1');
      expect(pie, isNotNull);
      expect(pie!.title, isNull);
      expect(pie.slices.length, 2);
    });

    test('computes slice fractions', () {
      final pie = parsePie('pie\n"A" : 30\n"B" : 10')!;
      expect(pie.total, 40);
      expect(pie.slices[0].fraction(pie.total), closeTo(0.75, 1e-9));
    });

    test('returns null for non-pie diagrams', () {
      expect(parsePie('graph TD;\nA-->B;'), isNull);
      expect(parsePie('sequenceDiagram\nA->>B: hi'), isNull);
    });

    test('returns null when there are no valid slices', () {
      expect(parsePie('pie title Empty'), isNull);
    });
  });
}
