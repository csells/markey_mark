import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_gantt.dart';

void main() {
  group('parseGantt', () {
    test('parses title, sections and tasks with durations', () {
      final g = parseGantt(
          'gantt\ntitle My Plan\ndateFormat YYYY-MM-DD\n'
          'section Design\nSpec :a1, 2024-01-01, 10d\nBuild :after a1, 20d\n'
          'section Launch\nShip : 2024-02-01, 5d');
      expect(g, isNotNull);
      expect(g!.title, 'My Plan');
      expect(g.tasks.length, 3);
      expect(g.tasks[0].name, 'Spec');
      expect(g.tasks[0].durationDays, 10);
      expect(g.tasks[0].section, 'Design');
      expect(g.tasks[1].durationDays, 20);
      expect(g.tasks[2].section, 'Launch');
      expect(g.tasks[2].durationDays, 5);
    });

    test('ignores directives and tolerates missing durations', () {
      final g = parseGantt('gantt\nsection S\nTask A : 2024-01-01, 3d')!;
      expect(g.tasks.single.name, 'Task A');
      expect(g.tasks.single.durationDays, 3);
    });

    test('returns null for non-gantt diagrams', () {
      expect(parseGantt('graph TD\nA-->B'), isNull);
      expect(parseGantt('pie\n"A":1'), isNull);
    });

    test('returns null with no tasks', () {
      expect(parseGantt('gantt\ntitle Empty'), isNull);
    });
  });
}
