import 'package:meta/meta.dart';

import '../model/document.dart';
import '../model/selection.dart';
import 'operations.dart';

/// A group of [operations] applied atomically and undone as one unit, together
/// with the selection before and after.
@immutable
final class EditTransaction {
  const EditTransaction({
    required this.operations,
    this.selectionBefore,
    this.selectionAfter,
    this.tag,
  });

  final List<Operation> operations;
  final DocumentSelection? selectionBefore;
  final DocumentSelection? selectionAfter;

  /// Optional label used by undo-grouping heuristics (e.g. `'typing'`,
  /// `'input-rule'`). Input-rule transactions are never merged with typing.
  final String? tag;

  bool get isEmpty => operations.isEmpty;

  /// Applies all operations in order.
  Document apply(Document doc) {
    var d = doc;
    for (final op in operations) {
      d = op.apply(d);
    }
    return d;
  }

  /// The transaction that exactly undoes this one: inverse operations in
  /// reverse order, with selections swapped.
  EditTransaction inverse() => EditTransaction(
        operations: [for (final op in operations.reversed) op.inverse()],
        selectionBefore: selectionAfter,
        selectionAfter: selectionBefore,
        tag: tag,
      );

  @override
  String toString() =>
      'EditTransaction(${operations.length} ops${tag != null ? ', $tag' : ''})';
}
