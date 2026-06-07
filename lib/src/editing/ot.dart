// Operational transformation for the block-level operation log — the
// concurrency-resolution layer over the same op log the editor and
// collaboration session use.
//
// Given two operations generated against the *same* base document,
// transformOperation rewrites one so it can be applied after the other,
// preserving each edit's intent and guaranteeing both peers converge (the TP1
// property). Structural edits (insert/delete blocks) are reconciled by shifting
// indices; a genuine conflict — two concurrent replaces of the *same* block —
// is resolved by a deterministic tieBreak (e.g. derived from a site id) so the
// same side wins everywhere.

import 'operations.dart';
import 'transaction.dart';

/// Index carried by every [Operation].
int _indexOf(Operation op) => switch (op) {
      InsertNodeOp(:final index) => index,
      DeleteNodeOp(:final index) => index,
      ReplaceNodeOp(:final index) => index,
    };

Operation _withIndex(Operation op, int index) => switch (op) {
      InsertNodeOp(:final node) => InsertNodeOp(index, node),
      DeleteNodeOp(:final node) => DeleteNodeOp(index, node),
      ReplaceNodeOp(:final before, :final after) =>
        ReplaceNodeOp(index, before, after),
    };

/// Transforms [op] so it applies cleanly after [against] (both built against the
/// same base). Returns null when [op] becomes a no-op (e.g. it targeted a block
/// that [against] deleted, or it lost a same-block conflict). [tieBreak] is true
/// when [op] should win a same-target conflict.
Operation? transformOperation(Operation op, Operation against,
    {required bool tieBreak}) {
  final ai = _indexOf(against);
  final oi = _indexOf(op);

  switch (against) {
    case InsertNodeOp():
      if (oi > ai) return _withIndex(op, oi + 1);
      if (oi < ai) return op;
      // Same index: an inserting op may go first if it wins; anything else is
      // pushed below the inserted node.
      if (op is InsertNodeOp) return tieBreak ? op : _withIndex(op, oi + 1);
      return _withIndex(op, oi + 1);

    case DeleteNodeOp():
      if (oi > ai) return _withIndex(op, oi - 1);
      if (oi < ai) return op;
      // Same index: the targeted block was deleted concurrently.
      if (op is InsertNodeOp) return op; // insert where the block was — still valid
      return null; // replacing/deleting a deleted block is a no-op

    case ReplaceNodeOp(:final after):
      // Replaces don't move indices; only a same-block replace conflicts.
      if (op is ReplaceNodeOp && oi == ai) {
        if (!tieBreak) return null; // op lost
        // op won: rebase its `before` onto the other's result so it still applies.
        return ReplaceNodeOp(oi, after, op.after);
      }
      return op;
  }
}

/// Transforms every operation of [incoming] against every operation of
/// [against], dropping any that become no-ops. Use to rebase a remote
/// transaction onto local concurrent edits before applying it.
EditTransaction transformTransaction(
    EditTransaction incoming, EditTransaction against,
    {required bool tieBreak}) {
  final ops = <Operation>[];
  for (final op in incoming.operations) {
    Operation? cur = op;
    for (final other in against.operations) {
      if (cur == null) break;
      cur = transformOperation(cur, other, tieBreak: tieBreak);
    }
    if (cur != null) ops.add(cur);
  }
  return EditTransaction(
    operations: ops,
    selectionBefore: incoming.selectionBefore,
    selectionAfter: incoming.selectionAfter,
    tag: incoming.tag,
  );
}
