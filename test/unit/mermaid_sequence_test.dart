import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_sequence.dart';

void main() {
  group('parseSequence', () {
    test('parses explicit participants and messages', () {
      final s = parseSequence(
          'sequenceDiagram\nparticipant Alice\nparticipant Bob\n'
          'Alice->>Bob: Hello\nBob-->>Alice: Hi');
      expect(s, isNotNull);
      expect(s!.participants, ['Alice', 'Bob']);
      expect(s.messages.length, 2);
      expect(s.messages[0].from, 'Alice');
      expect(s.messages[0].to, 'Bob');
      expect(s.messages[0].text, 'Hello');
      expect(s.messages[0].dashed, isFalse);
      expect(s.messages[1].dashed, isTrue);
    });

    test('infers participants from messages in first-seen order', () {
      final s = parseSequence('sequenceDiagram\nB->>A: hi\nA->>C: yo')!;
      expect(s.participants, ['B', 'A', 'C']);
    });

    test('supports "participant X as Label"', () {
      final s = parseSequence('sequenceDiagram\nparticipant A as Alice\nA->>A: note')!;
      expect(s.participants, ['A']);
      expect(s.labelFor('A'), 'Alice');
    });

    test('returns null for non-sequence diagrams', () {
      expect(parseSequence('pie\n"A":1'), isNull);
      expect(parseSequence('graph TD;\nA-->B;'), isNull);
    });

    test('returns null when there are no messages', () {
      expect(parseSequence('sequenceDiagram\nparticipant A'), isNull);
    });
  });
}
