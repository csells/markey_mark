import 'dart:math';

/// A persistent (immutable, structure-sharing) indexed sequence backed by an
/// implicit treap. `get`, `replace`, `insert`, and `removeAt` are O(log n) and
/// share structure with the previous version, so an edit never copies the whole
/// sequence — the backbone for O(log n) document edits at any scale.
class PersistentList<E> {
  const PersistentList._(this._root);

  factory PersistentList.empty() => PersistentList._(null);

  factory PersistentList.of(Iterable<E> items) {
    _Node<E>? root;
    for (final item in items) {
      root = _merge(root, _Node<E>(item, _rng.nextInt(_priMax), null, null));
    }
    return PersistentList._(root);
  }

  final _Node<E>? _root;
  static final Random _rng = Random();
  static const int _priMax = 1 << 30;

  int get length => _size(_root);
  bool get isEmpty => _root == null;

  E operator [](int index) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, this, 'index', null, length);
    }
    var node = _root!;
    var i = index;
    while (true) {
      final ls = _size(node.left);
      if (i < ls) {
        node = node.left!;
      } else if (i == ls) {
        return node.value;
      } else {
        i -= ls + 1;
        node = node.right!;
      }
    }
  }

  /// Returns a copy with index [index] set to [value] (O(log n), structure-shared).
  PersistentList<E> replace(int index, E value) =>
      PersistentList._(_replace(_root, index, value));

  /// Returns a copy with [value] inserted at [index] (O(log n)).
  PersistentList<E> insert(int index, E value) {
    final (l, r) = _split(_root, index);
    final node = _Node<E>(value, _rng.nextInt(_priMax), null, null);
    return PersistentList._(_merge(_merge(l, node), r));
  }

  /// Returns a copy with the element at [index] removed (O(log n)).
  PersistentList<E> removeAt(int index) {
    final (l, rest) = _split(_root, index);
    final (_, r) = _split(rest, 1);
    return PersistentList._(_merge(l, r));
  }

  List<E> toList() {
    final out = <E>[];
    void walk(_Node<E>? n) {
      if (n == null) return;
      walk(n.left);
      out.add(n.value);
      walk(n.right);
    }

    walk(_root);
    return out;
  }

  Iterable<E> get values sync* {
    Iterable<E> walk(_Node<E>? n) sync* {
      if (n == null) return;
      yield* walk(n.left);
      yield n.value;
      yield* walk(n.right);
    }

    yield* walk(_root);
  }

  static int _size<E>(_Node<E>? n) => n?.size ?? 0;

  static _Node<E> _replace<E>(_Node<E>? t, int i, E v) {
    final node = t!;
    final ls = _size(node.left);
    if (i < ls) {
      return _Node<E>(node.value, node.priority, _replace(node.left, i, v), node.right);
    }
    if (i == ls) {
      return _Node<E>(v, node.priority, node.left, node.right);
    }
    return _Node<E>(
        node.value, node.priority, node.left, _replace(node.right, i - ls - 1, v));
  }

  /// Splits into the first [k] elements and the rest.
  static (_Node<E>?, _Node<E>?) _split<E>(_Node<E>? t, int k) {
    if (t == null) return (null, null);
    final ls = _size(t.left);
    if (k <= ls) {
      final (l, r) = _split(t.left, k);
      return (l, _Node<E>(t.value, t.priority, r, t.right));
    } else {
      final (l, r) = _split(t.right, k - ls - 1);
      return (_Node<E>(t.value, t.priority, t.left, l), r);
    }
  }

  static _Node<E>? _merge<E>(_Node<E>? a, _Node<E>? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a.priority >= b.priority) {
      return _Node<E>(a.value, a.priority, a.left, _merge(a.right, b));
    } else {
      return _Node<E>(b.value, b.priority, _merge(a, b.left), b.right);
    }
  }
}

class _Node<E> {
  _Node(this.value, this.priority, this.left, this.right)
      : size = 1 + PersistentList._size(left) + PersistentList._size(right);
  final E value;
  final int priority;
  final int size;
  final _Node<E>? left;
  final _Node<E>? right;
}
