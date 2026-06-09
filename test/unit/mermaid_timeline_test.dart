import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_timeline.dart';

void main() {
  group('parseTimeline', () {
    const source = '''
timeline
    title History of Social Media
    2002 : LinkedIn
    2004 : Facebook : Google
    2005 : YouTube
''';

    test('parses title and periods', () {
      final t = parseTimeline(source);
      expect(t, isNotNull);
      expect(t!.title, 'History of Social Media');
      expect(t.periods.length, 3);
      expect(t.periods[0].label, '2002');
      expect(t.periods[1].label, '2004');
    });

    test('parses multiple events per period', () {
      final t = parseTimeline(source)!;
      expect(t.periods[0].events, ['LinkedIn']);
      expect(t.periods[1].events, ['Facebook', 'Google']);
    });

    test('groups periods into sections when present', () {
      final t = parseTimeline('''
timeline
    section 2000s
      2002 : LinkedIn
      2004 : Facebook
    section 2010s
      2010 : Pinterest
''')!;
      expect(t.sections.length, 2);
      expect(t.sections[0].name, '2000s');
      expect(t.sections[0].periods.length, 2);
      expect(t.sections[1].periods.single.label, '2010');
    });

    test('parses without a title', () {
      final t = parseTimeline('timeline\n2002 : LinkedIn')!;
      expect(t.title, isNull);
      expect(t.periods.single.label, '2002');
    });

    test('returns null for non-timeline diagrams', () {
      expect(parseTimeline('pie\n"A" : 1'), isNull);
      expect(parseTimeline('journey\nsection S\n Task: 4: Me'), isNull);
    });

    test('returns null when there are no periods', () {
      expect(parseTimeline('timeline\ntitle Empty'), isNull);
    });
  });
}
