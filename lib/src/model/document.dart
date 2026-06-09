import 'package:flutter/foundation.dart' show listEquals;

import 'node.dart';
import 'persistent_list.dart';

/// An immutable snapshot of the document: an ordered sequence of block [nodes].
///
/// Backed by a [PersistentList] (an implicit treap) so edits are O(log n) and
/// share structure — a keystroke never copies the whole sequence. An id→index
/// cache (carried across structure-preserving replaces) makes [indexOfId] /
/// [nodeById] O(1) on the editing hot path. There is always at least one node so
/// the caret always has a home.
///
/// Logically immutable (value semantics by content); the `_idIndex` /
/// `_materialized` fields are lazy memoization caches only.
final class Document {
  Document(List<Node> nodes)
      : _seq = PersistentList<Node>.of(
            nodes.isEmpty ? [TextBlockNode.paragraph()] : nodes);

  Document._fromSeq(this._seq, this._idIndex);

  /// An empty document containing a single empty paragraph.
  factory Document.empty() => Document([TextBlockNode.paragraph()]);

  final PersistentList<Node> _seq;

  /// Lazily-built id→index map, carried forward across `replaceAt` (which keeps
  /// ids and positions), rebuilt after inserts/removes.
  Map<String, int>? _idIndex;

  /// Lazily-materialized node list for [nodes] (iteration/compat paths only).
  List<Node>? _materialized;

  /// Total nodes visited building the id index — a test hook proving id lookup
  /// is O(1) on the hot path (no per-keystroke linear scans).
  static int debugIdScans = 0;

  int get length => _seq.length;

  /// The nodes as a List (materialized lazily and cached). Avoid on the hot
  /// path — prefer [length] + [nodeAt], which are O(1)/O(log n).
  List<Node> get nodes => _materialized ??= List.unmodifiable(_seq.toList());

  /// The node at [index] — O(log n), no materialization.
  Node nodeAt(int index) => _seq[index];

  bool get isEmpty =>
      _seq.length == 1 &&
      _seq[0] is TextBlockNode &&
      (_seq[0] as TextBlockNode).delta.isEmpty;

  Map<String, int> get _index {
    var idx = _idIndex;
    if (idx == null) {
      idx = <String, int>{};
      var i = 0;
      for (final n in _seq.values) {
        idx[n.id] = i++;
      }
      debugIdScans += _seq.length;
      _idIndex = idx;
    }
    return idx;
  }

  Node? nodeById(String id) {
    final i = _index[id];
    return i == null ? null : _seq[i];
  }

  int indexOfId(String id) => _index[id] ?? -1;

  Node? nodeBefore(String id) {
    final i = indexOfId(id);
    return i > 0 ? _seq[i - 1] : null;
  }

  Node? nodeAfter(String id) {
    final i = indexOfId(id);
    return (i >= 0 && i < _seq.length - 1) ? _seq[i + 1] : null;
  }

  /// Returns a new document with [node] inserted at [index] (O(log n)).
  Document insertAt(int index, Node node) =>
      Document._fromSeq(_seq.insert(index, node), null);

  /// Returns a new document with the node at [index] removed (O(log n)).
  Document removeAt(int index) =>
      Document._fromSeq(_seq.removeAt(index), null);

  /// Returns a new document with the node at [index] replaced (O(log n)).
  /// Replace preserves ids and positions, so the id→index cache is carried.
  Document replaceAt(int index, Node node) =>
      Document._fromSeq(_seq.replace(index, node), _idIndex);

  /// Replaces the node with id [id] (no-op if absent).
  Document replaceById(String id, Node node) {
    final i = indexOfId(id);
    return i < 0 ? this : replaceAt(i, node);
  }

  @override
  bool operator ==(Object other) =>
      other is Document && listEquals(other.nodes, nodes);

  @override
  int get hashCode => Object.hashAll(nodes);

  @override
  String toString() => 'Document(${_seq.length} nodes)';
}
