import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/editing/delta_ot.dart';
import 'package:markey_mark/src/model/attributes.dart';
import 'package:markey_mark/src/model/delta.dart';

/// Character-level operational transform for rich-text [Delta]s — the change
/// model (retain/insert/delete) that lets concurrent edits to the *same* block
/// (inserts, deletes, and formatting) merge and converge, not just last-writer-
/// wins.
void main() {
  Delta d(String s) => Delta.text(s);

  group('diff + apply round-trip', () {
    void roundTrip(Delta before, Delta after) {
      final change = DeltaChange.diff(before, after);
      expect(change.applyTo(before), after,
          reason: 'diff($before -> $after).apply should reproduce after');
    }

    test('insertion', () => roundTrip(d('hello'), d('helXlo')));
    test('deletion', () => roundTrip(d('hello'), d('hlo')));
    test('replacement', () => roundTrip(d('hello'), d('heY world')));
    test('prepend / append', () {
      roundTrip(d('hello'), d('Xhello'));
      roundTrip(d('hello'), d('helloX'));
    });
    test('formatting (same text, new attributes)', () {
      final before = d('hello');
      final after = before.format(0, 5, const {InlineAttr.bold: true});
      roundTrip(before, after);
    });
    test('empty <-> non-empty', () {
      roundTrip(Delta.empty(), d('hi'));
      roundTrip(d('hi'), Delta.empty());
    });
  });

  group('transform convergence (TP1)', () {
    // Both changes are made against `base`; after transforming each against the
    // other, applying in either order must reach the same document.
    void converge(Delta base, Delta a, Delta b) {
      final ca = DeltaChange.diff(base, a);
      final cb = DeltaChange.diff(base, b);
      // a wins ties (priority), b loses.
      final bPrime = ca.transform(cb, priority: true);
      final aPrime = cb.transform(ca, priority: false);
      final left = bPrime.applyTo(ca.applyTo(base));
      final right = aPrime.applyTo(cb.applyTo(base));
      expect(left, right, reason: 'must converge: $left vs $right');
    }

    test('concurrent insertions at different offsets', () {
      converge(d('hello'), d('Ahello'), d('helloB'));
    });
    test('concurrent insertions at the same offset', () {
      converge(d('hello'), d('Xhello'), d('Yhello'));
    });
    test('concurrent deletions (overlapping)', () {
      converge(d('hello world'), d('hello'), d('world'));
    });
    test('delete vs insert in the same region', () {
      converge(d('hello'), d('he!llo'), d('ho'));
    });
    test('format vs insert', () {
      final base = d('hello');
      converge(base, base.format(0, 5, const {InlineAttr.bold: true}),
          d('helloX'));
    });
    test('concurrent formats', () {
      final base = d('hello');
      converge(base, base.format(0, 5, const {InlineAttr.bold: true}),
          base.format(0, 5, const {InlineAttr.italic: true}));
    });
  });

  test('property: random concurrent edits always converge', () {
    final rng = Random(11);
    Delta randEdit(Delta base) {
      final t = base.toPlainText();
      final op = rng.nextInt(3);
      if (t.isEmpty || op == 0) {
        final at = rng.nextInt(t.length + 1);
        return base.insert(at, String.fromCharCode(0x61 + rng.nextInt(5)));
      } else if (op == 1) {
        final s = rng.nextInt(t.length);
        final e = s + 1 + rng.nextInt(t.length - s);
        return base.delete(s, e);
      } else {
        final s = rng.nextInt(t.length);
        final e = s + 1 + rng.nextInt(t.length - s);
        return base.format(s, e, const {InlineAttr.bold: true});
      }
    }

    for (var i = 0; i < 500; i++) {
      final base = Delta.text('abcdef');
      final a = randEdit(base);
      final b = randEdit(base);
      final ca = DeltaChange.diff(base, a);
      final cb = DeltaChange.diff(base, b);
      final left = ca.transform(cb, priority: true).applyTo(ca.applyTo(base));
      final right = cb.transform(ca, priority: false).applyTo(cb.applyTo(base));
      expect(left.toPlainText(), right.toPlainText(),
          reason: 'iteration $i: a=$a b=$b');
    }
  });
}
