import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/model/fractional_index.dart';

/// Fractional indexing: order keys that let a block be inserted between any two
/// neighbours without renumbering, so concurrent reorders/inserts from
/// different peers merge instead of colliding on an integer index.
void main() {
  String between(String? a, String? b) => FractionalIndex.keyBetween(a, b);

  test('keyBetween(null, null) is a valid non-empty key', () {
    final k = between(null, null);
    expect(k, isNotEmpty);
  });

  test('a key generated between two keys sorts strictly between them', () {
    final a = between(null, null);
    final b = between(a, null);
    expect(a.compareTo(b) < 0, isTrue);
    final mid = between(a, b);
    expect(a.compareTo(mid) < 0, isTrue);
    expect(mid.compareTo(b) < 0, isTrue);
  });

  test('appending at the end keeps ascending order', () {
    final keys = <String>[];
    String? last;
    for (var i = 0; i < 50; i++) {
      last = between(last, null);
      keys.add(last);
    }
    final sorted = [...keys]..sort();
    expect(keys, sorted);
  });

  test('prepending at the front keeps ascending order', () {
    final keys = <String>[];
    String? first;
    for (var i = 0; i < 50; i++) {
      first = between(null, first);
      keys.add(first);
    }
    expect(keys.reversed.toList(), [...keys]..sort());
  });

  test('property: 2000 random midpoint insertions stay strictly ordered', () {
    final rng = Random(42);
    // Start with two keys; repeatedly insert between a random adjacent pair.
    final keys = <String>[between(null, null)];
    keys.add(between(keys[0], null));
    for (var n = 0; n < 2000; n++) {
      final i = rng.nextInt(keys.length - 1);
      final mid = between(keys[i], keys[i + 1]);
      expect(keys[i].compareTo(mid) < 0, isTrue,
          reason: 'left=${keys[i]} mid=$mid');
      expect(mid.compareTo(keys[i + 1]) < 0, isTrue,
          reason: 'mid=$mid right=${keys[i + 1]}');
      keys.insert(i + 1, mid);
    }
    // The whole list is still strictly ascending.
    for (var i = 0; i < keys.length - 1; i++) {
      expect(keys[i].compareTo(keys[i + 1]) < 0, isTrue);
    }
  });

  test('keys never end in the lowest digit (no trailing-zero ambiguity)', () {
    final rng = Random(7);
    String? a;
    String? b;
    for (var i = 0; i < 200; i++) {
      final k = between(a, b);
      expect(k[k.length - 1], isNot('0'));
      if (rng.nextBool()) {
        a = k;
      } else {
        b = k;
      }
      if (a != null && b != null && a.compareTo(b) >= 0) {
        a = null;
        b = null;
      }
    }
  });
}
