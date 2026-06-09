import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/widget/ime_delta.dart';

/// The precise delta path replaces the old lossy `_diff` string-compare: the
/// platform tells us exactly what changed (including composing), so each
/// [TextEditingDelta] maps unambiguously to a (start, deleted, inserted) edit.
void main() {
  group('editFromDelta', () {
    test('insertion', () {
      const d = TextEditingDeltaInsertion(
        oldText: 'helo',
        textInserted: 'l',
        insertionOffset: 3,
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange.empty,
      );
      expect(editFromDelta(d), (3, 0, 'l'));
    });

    test('deletion', () {
      const d = TextEditingDeltaDeletion(
        oldText: 'hello',
        deletedRange: TextRange(start: 1, end: 3),
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
      );
      expect(editFromDelta(d), (1, 2, ''));
    });

    test('replacement (e.g. autocorrect of a whole word)', () {
      const d = TextEditingDeltaReplacement(
        oldText: 'teh end',
        replacementText: 'the',
        replacedRange: TextRange(start: 0, end: 3),
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange.empty,
      );
      expect(editFromDelta(d), (0, 3, 'the'));
    });

    test('non-text update (selection/composing only) yields no edit', () {
      const d = TextEditingDeltaNonTextUpdate(
        oldText: 'hello',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      expect(editFromDelta(d), isNull);
    });
  });
}
