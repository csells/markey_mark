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

import '../model/delta.dart';
import '../model/node.dart';
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
        // Character-level merge when both edits are pure insertions: rebase this
        // op's insertion onto the other's result so BOTH survive (two people
        // typing in the same paragraph keep their characters). Falls back to
        // last-writer-wins for deletes/replaces/formatting.
        final merged = _mergeInsertions(op, against, tieBreak: tieBreak);
        if (merged != null) return merged;
        if (!tieBreak) return null; // op lost
        return ReplaceNodeOp(oi, after, op.after);
      }
      return op;
  }
}

/// If both [op] and [against] are pure text insertions into the same block,
/// returns [op] rebased onto [against]'s result (so both insertions land);
/// otherwise null (caller falls back to last-writer-wins).
ReplaceNodeOp? _mergeInsertions(ReplaceNodeOp op, ReplaceNodeOp against,
    {required bool tieBreak}) {
  final mine = _asInsertion(op);
  final other = _asInsertion(against);
  if (mine == null || other == null) return null;
  final base = against.after;
  if (base is! TextBlockNode) return null;
  final (pos1, ins1) = mine;
  final (pos2, ins2) = other;
  // The other's insertion already shifted the text; place mine after it when it
  // starts later, or at the same point and mine loses the tie.
  final at = (pos2 < pos1 || (pos2 == pos1 && !tieBreak))
      ? pos1 + ins2.length
      : pos1;
  final d = base.delta;
  final clamped = at.clamp(0, d.length);
  final merged = d.slice(0, clamped).concat(ins1).concat(d.slice(clamped, d.length));
  return ReplaceNodeOp(op.index, base, base.copyWithDelta(merged));
}

/// Interprets a [ReplaceNodeOp] on a text block as a single insertion
/// `(offset, inserted)`, or null when it isn't a clean insertion.
(int, Delta)? _asInsertion(ReplaceNodeOp op) {
  final before = op.before;
  final after = op.after;
  if (before is! TextBlockNode || after is! TextBlockNode) return null;
  final b = before.delta;
  final a = after.delta;
  final insLen = a.length - b.length;
  if (insLen <= 0) return null; // not a pure insertion
  final bt = b.toPlainText();
  final at = a.toPlainText();
  var p = 0;
  while (p < bt.length && p < at.length && bt[p] == at[p]) {
    p++;
  }
  var s = 0;
  while (s < bt.length - p && s < at.length - p &&
      bt[bt.length - 1 - s] == at[at.length - 1 - s]) {
    s++;
  }
  // The inserted region must be exactly [p, a.length - s) and account for the
  // whole length delta (a clean single contiguous insertion).
  if (at.length - s - p != insLen) return null;
  return (p, a.slice(p, a.length - s));
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
