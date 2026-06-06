import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/model/attributes.dart';

void main() {
  group('attributesEqual', () {
    test('both empty/null are equal', () {
      expect(attributesEqual(null, null), isTrue);
      expect(attributesEqual(const {}, null), isTrue);
      expect(attributesEqual(null, const {}), isTrue);
      expect(attributesEqual(const {}, const {}), isTrue);
    });

    test('one empty one not is unequal', () {
      expect(attributesEqual(const {'bold': true}, null), isFalse);
      expect(attributesEqual(null, const {'bold': true}), isFalse);
    });

    test('same keys/values equal regardless of order', () {
      expect(
        attributesEqual(
          const {'bold': true, 'italic': true},
          const {'italic': true, 'bold': true},
        ),
        isTrue,
      );
    });

    test('different length unequal', () {
      expect(
        attributesEqual(const {'bold': true}, const {'bold': true, 'italic': true}),
        isFalse,
      );
    });

    test('different value unequal', () {
      expect(
        attributesEqual(const {'link': 'a'}, const {'link': 'b'}),
        isFalse,
      );
    });

    test('missing key unequal', () {
      expect(
        attributesEqual(const {'bold': true}, const {'italic': true}),
        isFalse,
      );
    });
  });

  group('normalizeAttributes', () {
    test('drops null and false', () {
      final n = normalizeAttributes({'bold': true, 'italic': false, 'x': null});
      expect(n, {'bold': true});
    });

    test('empty/null yield const empty', () {
      expect(normalizeAttributes(null), isEmpty);
      expect(normalizeAttributes(const {}), isEmpty);
    });

    test('result is unmodifiable', () {
      final n = normalizeAttributes({'bold': true});
      expect(() => n['x'] = 1, throwsUnsupportedError);
    });
  });

  test('InlineAttr constants', () {
    expect(InlineAttr.bold, 'bold');
    expect(InlineAttr.italic, 'italic');
    expect(InlineAttr.strike, 'strike');
    expect(InlineAttr.code, 'code');
    expect(InlineAttr.link, 'link');
    expect(InlineAttr.math, 'math');
  });
}
