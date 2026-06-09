import 'package:meta/meta.dart';

import '../model/document.dart';
import '../model/node.dart';

/// A single, invertible mutation of the [Document].
///
/// Every operation carries enough state to invert itself with zero document
/// access (the appflowy "inverse-by-construction" pattern), which is what makes
/// undo/redo trivial and correct. Because nodes are immutable value objects, a
/// text edit and an attribute edit are both just a [ReplaceNodeOp].
@immutable
sealed class Operation {
  const Operation();

  /// Returns a new document with this operation applied.
  Document apply(Document doc);

  /// The operation that exactly undoes this one.
  Operation inverse();
}

/// Inserts [node] at [index].
@immutable
final class InsertNodeOp extends Operation {
  const InsertNodeOp(this.index, this.node);
  final int index;
  final Node node;

  @override
  Document apply(Document doc) => doc.insertAt(index, node);

  @override
  Operation inverse() => DeleteNodeOp(index, node);

  @override
  String toString() => 'InsertNodeOp($index, ${node.id})';
}

/// Deletes the node at [index] (which must equal [node]).
@immutable
final class DeleteNodeOp extends Operation {
  const DeleteNodeOp(this.index, this.node);
  final int index;
  final Node node;

  @override
  Document apply(Document doc) => doc.removeAt(index);

  @override
  Operation inverse() => InsertNodeOp(index, node);

  @override
  String toString() => 'DeleteNodeOp($index, ${node.id})';
}

/// Replaces the node at [index] (covers both text and attribute changes).
@immutable
final class ReplaceNodeOp extends Operation {
  const ReplaceNodeOp(this.index, this.before, this.after);
  final int index;
  final Node before;
  final Node after;

  @override
  Document apply(Document doc) => doc.replaceAt(index, after);

  @override
  Operation inverse() => ReplaceNodeOp(index, after, before);

  @override
  String toString() => 'ReplaceNodeOp($index, ${before.id})';
}
