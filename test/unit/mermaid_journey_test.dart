import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_journey.dart';

void main() {
  group('parseJourney', () {
    const source = '''
journey
    title My working day
    section Go to work
      Make tea: 5: Me
      Go upstairs: 3: Me
      Do work: 1: Me, Cat
    section Go home
      Go downstairs: 5: Me
      Sit down: 3: Me
''';

    test('parses title, sections and tasks', () {
      final j = parseJourney(source);
      expect(j, isNotNull);
      expect(j!.title, 'My working day');
      expect(j.sections.length, 2);
      expect(j.sections[0].name, 'Go to work');
      expect(j.sections[0].tasks.length, 3);
      expect(j.sections[1].name, 'Go home');
      expect(j.sections[1].tasks.length, 2);
    });

    test('parses task name, score and actors', () {
      final j = parseJourney(source)!;
      final t = j.sections[0].tasks[2];
      expect(t.name, 'Do work');
      expect(t.score, 1);
      expect(t.actors, ['Me', 'Cat']);
    });

    test('clamps score to the 1..5 range', () {
      final j = parseJourney('journey\nsection S\n  Big: 9: Me\n  Tiny: 0: Me')!;
      expect(j.sections[0].tasks[0].score, 5);
      expect(j.sections[0].tasks[1].score, 1);
    });

    test('parses without a title', () {
      final j = parseJourney('journey\nsection S\n  Task: 4: Me')!;
      expect(j.title, isNull);
      expect(j.sections.single.tasks.single.name, 'Task');
    });

    test('collects the distinct actor set in first-seen order', () {
      final j = parseJourney(source)!;
      expect(j.actors, ['Me', 'Cat']);
    });

    test('returns null for non-journey diagrams', () {
      expect(parseJourney('pie\n"A" : 1'), isNull);
      expect(parseJourney('graph TD;\nA-->B;'), isNull);
    });

    test('returns null when there are no tasks', () {
      expect(parseJourney('journey\ntitle Empty'), isNull);
    });
  });
}
