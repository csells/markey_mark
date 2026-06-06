import 'package:flutter/foundation.dart';

import 'node.dart';

/// An immutable snapshot of the document: an ordered list of block [nodes].
///
/// The vertical slice uses a flat list of blocks (paragraph/heading). The full
/// model is a tree (lists/quotes/tables have children); this type is the seam
/// where that generalizes. There is always at least one node so the caret
/// always has a home.
@immutable
final class Document {
  Document(List<Node> nodes)
      : nodes = List.unmodifiable(
          nodes.isEmpty ? [TextBlockNode.paragraph()] : nodes,
        );

  /// An empty document containing a single empty paragraph.
  factory Document.empty() => Document([TextBlockNode.paragraph()]);

  final List<Node> nodes;

  int get length => nodes.length;
  bool get isEmpty =>
      nodes.length == 1 &&
      nodes.first is TextBlockNode &&
      (nodes.first as TextBlockNode).delta.isEmpty;

  Node? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  int indexOfId(String id) {
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].id == id) return i;
    }
    return -1;
  }

  Node? nodeBefore(String id) {
    final i = indexOfId(id);
    return i > 0 ? nodes[i - 1] : null;
  }

  Node? nodeAfter(String id) {
    final i = indexOfId(id);
    return (i >= 0 && i < nodes.length - 1) ? nodes[i + 1] : null;
  }

  /// Returns a new document with [node] inserted at [index].
  Document insertAt(int index, Node node) {
    final copy = [...nodes]..insert(index, node);
    return Document(copy);
  }

  /// Returns a new document with the node at [index] removed.
  Document removeAt(int index) {
    final copy = [...nodes]..removeAt(index);
    return Document(copy);
  }

  /// Returns a new document with the node at [index] replaced by [node].
  Document replaceAt(int index, Node node) {
    final copy = [...nodes];
    copy[index] = node;
    return Document(copy);
  }

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
  String toString() => 'Document(${nodes.length} nodes)';
}
