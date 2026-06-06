import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/model/delta.dart';

void main() {
  group('TextRun', () {
    test('normalizes attributes and reports length/empty', () {
      final r = TextRun('hi', {'bold': true, 'italic': false});
      expect(r.attributes, {'bold': true});
      expect(r.length, 2);
      expect(r.isEmpty, isFalse);
      expect(TextRun('').isEmpty, isTrue);
    });

    test('equality and hashCode', () {
      expect(TextRun('a', {'bold': true}), TextRun('a', {'bold': true}));
      expect(TextRun('a', {'bold': true}) == TextRun('a'), isFalse);
      expect(TextRun('a').hashCode, isA<int>());
    });

    test('copyWith', () {
      final r = TextRun('a', {'bold': true});
      expect(r.copyWith(text: 'b'), TextRun('b', {'bold': true}));
      expect(r.copyWith(attributes: const {}), TextRun('a'));
    });

    test('toString escapes newlines', () {
      expect(TextRun('a\nb').toString(), contains(r'\n'));
    });
  });

  group('Delta construction', () {
    test('empty', () {
      final d = Delta.empty();
      expect(d.isEmpty, isTrue);
      expect(d.isNotEmpty, isFalse);
      expect(d.length, 0);
      expect(d.toPlainText(), '');
    });

    test('isNotEmpty', () {
      expect(Delta.text('x').isNotEmpty, isTrue);
    });

    test('text factory', () {
      expect(Delta.text('').isEmpty, isTrue);
      final d = Delta.text('hi', {'bold': true});
      expect(d.toPlainText(), 'hi');
      expect(d.runs.single.attributes, {'bold': true});
    });

    test('normalizes adjacent equal runs on construction', () {
      final d = Delta([
        TextRun('a', {'bold': true}),
        TextRun('b', {'bold': true}),
        TextRun('c'),
      ]);
      expect(d.runs.length, 2);
      expect(d.runs[0], TextRun('ab', {'bold': true}));
      expect(d.runs[1], TextRun('c'));
    });

    test('drops empty runs', () {
      final d = Delta([TextRun(''), TextRun('a')]);
      expect(d.runs.length, 1);
    });
  });

  group('Delta.slice', () {
    final d = Delta([
      TextRun('Hello ', {'bold': true}),
      TextRun('World'),
    ]);

    test('full and partial slices', () {
      expect(d.slice(0).toPlainText(), 'Hello World');
      expect(d.slice(0, 5).toPlainText(), 'Hello');
      expect(d.slice(6).toPlainText(), 'World');
      expect(d.slice(3, 8).toPlainText(), 'lo Wo');
    });

    test('empty slice', () {
      expect(d.slice(3, 3).isEmpty, isTrue);
    });

    test('preserves attributes within slice', () {
      final s = d.slice(0, 5);
      expect(s.runs.single.attributes, {'bold': true});
    });

    test('throws on out of range', () {
      expect(() => d.slice(-1), throwsRangeError);
      expect(() => d.slice(0, 100), throwsRangeError);
      expect(() => d.slice(5, 2), throwsRangeError);
    });
  });

  group('Delta edits', () {
    test('insert at boundaries and middle', () {
      var d = Delta.text('Hello');
      d = d.insert(5, ' World');
      expect(d.toPlainText(), 'Hello World');
      d = d.insert(0, '> ');
      expect(d.toPlainText(), '> Hello World');
      d = d.insert(2, 'X');
      expect(d.toPlainText(), '> XHello World');
    });

    test('insert empty is a no-op', () {
      final d = Delta.text('a');
      expect(d.insert(0, ''), d);
    });

    test('insert out of range throws', () {
      expect(() => Delta.text('a').insert(5, 'x'), throwsRangeError);
    });

    test('delete', () {
      final d = Delta.text('Hello World');
      expect(d.delete(5, 11).toPlainText(), 'Hello');
      expect(d.delete(0, 6).toPlainText(), 'World');
      expect(d.delete(3, 3), d);
    });

    test('concat normalizes across the seam', () {
      final a = Delta.text('foo', {'bold': true});
      final b = Delta.text('bar', {'bold': true});
      final c = a.concat(b);
      expect(c.runs.length, 1);
      expect(c.toPlainText(), 'foobar');
    });
  });

  group('Delta.format', () {
    test('applies a mark over a range', () {
      final d = Delta.text('Hello World').format(0, 5, {'bold': true});
      expect(d.runs.first, TextRun('Hello', {'bold': true}));
      expect(d.runs.last, TextRun(' World'));
    });

    test('removing a mark with null/false', () {
      var d = Delta.text('Hello', {'bold': true});
      d = d.format(0, 5, {'bold': null});
      expect(d.runs.single.attributes, isEmpty);
    });

    test('format empty range is a no-op', () {
      final d = Delta.text('Hello');
      expect(d.format(2, 2, {'bold': true}), d);
    });

    test('combines with existing marks', () {
      var d = Delta.text('Hello', {'bold': true});
      d = d.format(0, 5, {'italic': true});
      expect(d.runs.single.attributes, {'bold': true, 'italic': true});
    });
  });

  group('Delta.isFormatted', () {
    test('true only when fully formatted', () {
      final d = Delta([
        TextRun('ab', {'bold': true}),
        TextRun('cd'),
      ]);
      expect(d.isFormatted(0, 2, 'bold'), isTrue);
      expect(d.isFormatted(0, 4, 'bold'), isFalse);
      expect(d.isFormatted(2, 4, 'bold'), isFalse);
    });

    test('empty range false', () {
      expect(Delta.text('a').isFormatted(0, 0, 'bold'), isFalse);
    });
  });

  group('Delta.attributesAt', () {
    final d = Delta([
      TextRun('ab', {'bold': true}),
      TextRun('cd'),
    ]);

    test('index 0 inherits nothing', () {
      expect(d.attributesAt(0), isEmpty);
    });

    test('inherits preceding character', () {
      expect(d.attributesAt(1), {'bold': true});
      expect(d.attributesAt(2), {'bold': true});
      expect(d.attributesAt(3), isEmpty);
    });

    test('empty delta', () {
      expect(Delta.empty().attributesAt(0), isEmpty);
    });
  });

  group('Delta json + equality', () {
    test('round trips through json', () {
      final d = Delta([
        TextRun('a', {'bold': true}),
        TextRun('b'),
      ]);
      final j = d.toJson();
      expect(Delta.fromJson(j), d);
    });

    test('equality and hashCode', () {
      expect(Delta.text('a'), Delta.text('a'));
      expect(Delta.text('a') == Delta.text('b'), isFalse);
      expect(Delta.text('a').hashCode, Delta.text('a').hashCode);
      // ignore: unrelated_type_equality_checks
      expect(Delta.text('a') == 'a', isFalse);
    });

    test('toString', () {
      expect(Delta.text('a').toString(), startsWith('Delta('));
    });
  });
}
