import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/model/persistent_list.dart';

/// A persistent (immutable, structure-sharing) indexed sequence with O(log n)
/// get/replace/insert/removeAt — the backbone for O(log n) document edits
/// instead of O(n) list copies. Verified against a reference List over random
/// operation sequences (property-based).
void main() {
  test('empty / single / fromList basics', () {
    expect(PersistentList<int>.empty().length, 0);
    final l = PersistentList<int>.of([1, 2, 3]);
    expect(l.length, 3);
    expect(l[0], 1);
    expect(l[2], 3);
    expect(l.toList(), [1, 2, 3]);
  });

  test('replace returns a new list and shares structure (original intact)', () {
    final a = PersistentList<int>.of([10, 20, 30]);
    final b = a.replace(1, 99);
    expect(b.toList(), [10, 99, 30]);
    expect(a.toList(), [10, 20, 30]); // unchanged — persistent
  });

  test('insert and removeAt', () {
    final a = PersistentList<int>.of([1, 2, 3]);
    expect(a.insert(1, 9).toList(), [1, 9, 2, 3]);
    expect(a.insert(0, 0).toList(), [0, 1, 2, 3]);
    expect(a.insert(3, 4).toList(), [1, 2, 3, 4]);
    expect(a.removeAt(1).toList(), [1, 3]);
    expect(a.toList(), [1, 2, 3]); // unchanged
  });

  test('property: matches a reference List over 4000 random ops', () {
    final r = Random(7);
    final ref = <int>[];
    var pl = PersistentList<int>.empty();
    for (var i = 0; i < 4000; i++) {
      final n = ref.length;
      final op = n == 0 ? 0 : r.nextInt(3);
      switch (op) {
        case 0: // insert
          final at = r.nextInt(n + 1);
          final v = r.nextInt(1 << 20);
          ref.insert(at, v);
          pl = pl.insert(at, v);
        case 1: // replace
          final at = r.nextInt(n);
          final v = r.nextInt(1 << 20);
          ref[at] = v;
          pl = pl.replace(at, v);
        case 2: // remove
          final at = r.nextInt(n);
          ref.removeAt(at);
          pl = pl.removeAt(at);
      }
      expect(pl.length, ref.length);
    }
    expect(pl.toList(), ref);
    // Random index reads agree.
    for (var i = 0; i < ref.length; i += 37) {
      expect(pl[i], ref[i]);
    }
  });

  test('stays balanced: 100k inserts then reads are fast (O(log n))', () {
    var pl = PersistentList<int>.empty();
    for (var i = 0; i < 100000; i++) {
      pl = pl.insert(pl.length, i);
    }
    expect(pl.length, 100000);
    // A handful of replaces near the end must not walk 100k elements.
    final sw = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      pl = pl.replace(99999, i);
    }
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(200),
        reason: '1000 replaces in a 100k list must be O(log n) each');
  });
}
