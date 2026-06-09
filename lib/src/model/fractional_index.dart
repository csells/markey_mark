/// Fractional indexing — generates a short, ordered string key strictly between
/// two neighbouring keys, so a block can be inserted/moved between any two
/// others **without renumbering**. Two peers inserting "between A and B"
/// concurrently produce different keys that both still sort between A and B, so
/// reorders merge instead of colliding on an integer index (the mergeable
/// ordering the collaboration layer builds on).
///
/// Keys are compared with plain [String.compareTo]. The algorithm treats a key
/// as a base-36 fraction in (0, 1) and emits the shortest digit string that
/// falls strictly between the bounds; keys never end in the lowest digit, so
/// `x` and `x0` can't denote the same fraction.
abstract final class FractionalIndex {
  static const String _digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  static const int _base = 36;

  /// A key strictly between [a] and [b] (either null = open boundary). Requires
  /// `a < b` when both are given.
  static String keyBetween(String? a, String? b) {
    if (a != null && b != null) {
      assert(a.compareTo(b) < 0, 'keyBetween requires a < b (a=$a, b=$b)');
    }
    return _avg(a ?? '', b);
  }

  static int _val(int codeUnit) {
    // '0'..'9'
    if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30;
    // 'a'..'z'
    return codeUnit - 0x61 + 10;
  }

  static String _digit(int v) => _digits[v];

  /// The shortest digit string strictly between [lower] (a key, '' = 0) and
  /// [upper] (a key, or null = 1.0).
  static String _avg(String lower, String? upper) {
    final sb = StringBuffer();
    var i = 0;
    while (true) {
      final lo = i < lower.length ? _val(lower.codeUnitAt(i)) : 0;
      // Once we've committed below `upper` (upper==null), the ceiling is the
      // open top of the range (`_base`); otherwise it's upper's i-th digit (or
      // 0 past its end — but `lower < upper` guarantees we branch before that).
      final hi = upper == null
          ? _base
          : (i < upper.length ? _val(upper.codeUnitAt(i)) : 0);
      if (lo + 1 < hi) {
        // Room between the digits: the midpoint digit ends the key.
        sb.write(_digit((lo + hi) ~/ 2));
        return sb.toString();
      }
      if (lo == hi) {
        // Digits equal: keep this digit and descend with both bounds.
        sb.write(_digit(lo));
        i++;
        continue;
      }
      // lo + 1 == hi: take lower's digit; any continuation stays below upper, so
      // the ceiling opens up and we find a key just above lower's remainder.
      sb.write(_digit(lo));
      i++;
      return (sb..write(_avg(lower.length > i ? lower.substring(i) : '', null)))
          .toString();
    }
  }
}
