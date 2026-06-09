import '../model/attributes.dart';
import '../model/delta.dart';

/// One operation of a [DeltaChange]: keep, insert, or remove characters.
sealed class ChangeOp {
  const ChangeOp();
}

/// Keep [n] characters of the base unchanged.
final class RetainOp extends ChangeOp {
  const RetainOp(this.n);
  final int n;
}

/// Remove [n] characters of the base.
final class DeleteOp extends ChangeOp {
  const DeleteOp(this.n);
  final int n;
}

/// Insert rich [content].
final class InsertOp extends ChangeOp {
  const InsertOp(this.content);
  final Delta content;
}

/// A **change** to a rich-text [Delta] — a sequence of retain/insert/delete ops
/// (the Quill/ot.js model). This is the layer that makes character-level
/// operational transform possible: a [Delta] stores document *state* (inserts
/// only), while a [DeltaChange] is an *edit*. Two concurrent edits to the same
/// block are reconciled with [transform] so inserts, deletes, and formatting all
/// merge and converge.
class DeltaChange {
  DeltaChange(List<ChangeOp> ops) : ops = List.unmodifiable(_merge(ops));

  final List<ChangeOp> ops;

  /// The minimal change turning [before] into [after] (a single contiguous
  /// edit, found by common prefix/suffix over (char, attributes) cells — exact
  /// for the one-action edits the editor produces).
  static DeltaChange diff(Delta before, Delta after) {
    final b = _cells(before);
    final a = _cells(after);
    var p = 0;
    while (p < b.length && p < a.length && _cellEq(b[p], a[p])) {
      p++;
    }
    var s = 0;
    while (s < b.length - p && s < a.length - p &&
        _cellEq(b[b.length - 1 - s], a[a.length - 1 - s])) {
      s++;
    }
    final ops = <ChangeOp>[];
    if (p > 0) ops.add(RetainOp(p));
    final delLen = b.length - p - s;
    if (delLen > 0) ops.add(DeleteOp(delLen));
    final ins = after.slice(p, a.length - s);
    if (ins.isNotEmpty) ops.add(InsertOp(ins));
    if (s > 0) ops.add(RetainOp(s));
    return DeltaChange(ops);
  }

  /// Applies this change to [base].
  Delta applyTo(Delta base) {
    var result = Delta.empty();
    var pos = 0;
    for (final op in ops) {
      switch (op) {
        case RetainOp(:final n):
          result = result.concat(base.slice(pos, pos + n));
          pos += n;
        case DeleteOp(:final n):
          pos += n;
        case InsertOp(:final content):
          result = result.concat(content);
      }
    }
    if (pos < base.length) result = result.concat(base.slice(pos, base.length));
    return result.normalized;
  }

  /// Transforms [other] so it applies after this change (both built against the
  /// same base). [priority] true means *this* change's concurrent inserts come
  /// first (so [other]'s inserts at the same point shift after them) — the
  /// deterministic tie-break. (The ot.js / quill-delta transform.)
  DeltaChange transform(DeltaChange other, {required bool priority}) {
    final out = <ChangeOp>[];
    final ti = _OpIter(ops);
    final oi = _OpIter(other.ops);
    while (ti.hasNext || oi.hasNext) {
      if (ti.peekIsInsert && (priority || !oi.peekIsInsert)) {
        out.add(RetainOp(ti.takeInsertLength())); // skip over this insert
      } else if (oi.peekIsInsert) {
        out.add(InsertOp(oi.takeInsert())); // keep other's insert
      } else {
        final len = ti.peekLength < oi.peekLength ? ti.peekLength : oi.peekLength;
        final mine = ti.take(len);
        final theirs = oi.take(len);
        if (mine is DeleteOp) {
          continue; // this deleted it; other's retain/delete on it vanishes
        } else if (theirs is DeleteOp) {
          out.add(DeleteOp(len)); // keep other's delete
        } else {
          out.add(RetainOp(len)); // both retain
        }
      }
    }
    return DeltaChange(_chop(out));
  }

  // ── helpers ────────────────────────────────────────────────────────────

  static List<_Cell> _cells(Delta delta) {
    final out = <_Cell>[];
    for (final run in delta.runs) {
      for (final ch in run.text.split('')) {
        out.add(_Cell(ch, run.attributes));
      }
    }
    return out;
  }

  static bool _cellEq(_Cell a, _Cell b) =>
      a.ch == b.ch && attributesEqual(a.attrs, b.attrs);

  /// Merge adjacent same-kind ops (retain+retain, delete+delete, insert+insert).
  static List<ChangeOp> _merge(List<ChangeOp> ops) {
    final out = <ChangeOp>[];
    for (final op in ops) {
      if (op is RetainOp && op.n == 0) continue;
      if (op is DeleteOp && op.n == 0) continue;
      if (op is InsertOp && op.content.isEmpty) continue;
      if (out.isEmpty) {
        out.add(op);
        continue;
      }
      final last = out.last;
      if (last is RetainOp && op is RetainOp) {
        out[out.length - 1] = RetainOp(last.n + op.n);
      } else if (last is DeleteOp && op is DeleteOp) {
        out[out.length - 1] = DeleteOp(last.n + op.n);
      } else if (last is InsertOp && op is InsertOp) {
        out[out.length - 1] = InsertOp(last.content.concat(op.content));
      } else {
        out.add(op);
      }
    }
    return out;
  }

  /// Drop a trailing retain (it's a no-op).
  static List<ChangeOp> _chop(List<ChangeOp> ops) {
    final merged = _merge(ops);
    if (merged.isNotEmpty && merged.last is RetainOp) {
      return merged.sublist(0, merged.length - 1);
    }
    return merged;
  }

  @override
  String toString() => 'DeltaChange($ops)';
}

class _Cell {
  _Cell(this.ch, this.attrs);
  final String ch;
  final Attributes attrs;
}

/// Walks a change op-by-op, splitting the current op when only part of it is
/// consumed (`take`/`takeInsert`).
class _OpIter {
  _OpIter(this._ops);
  final List<ChangeOp> _ops;
  int _i = 0;
  int _offset = 0; // chars consumed of the current op

  bool get hasNext => _i < _ops.length;

  ChangeOp get _cur => _ops[_i];

  bool get peekIsInsert => hasNext && _cur is InsertOp;

  int get peekLength {
    if (!hasNext) return 1 << 30; // treat exhausted side as infinite retain
    final op = _cur;
    return switch (op) {
          RetainOp(:final n) => n,
          DeleteOp(:final n) => n,
          InsertOp(:final content) => content.length,
        } -
        _offset;
  }

  /// Consumes [len] characters of a retain/delete op, returning the consumed op.
  ChangeOp take(int len) {
    if (!hasNext) return RetainOp(len); // exhausted → implicit retain
    final op = _cur;
    final remaining = peekLength;
    final ChangeOp consumed = op is DeleteOp ? DeleteOp(len) : RetainOp(len);
    if (len >= remaining) {
      _i++;
      _offset = 0;
    } else {
      _offset += len;
    }
    return consumed;
  }

  int takeInsertLength() {
    final content = (_cur as InsertOp).content;
    final len = content.length - _offset;
    _i++;
    _offset = 0;
    return len;
  }

  Delta takeInsert() {
    final content = (_cur as InsertOp).content;
    final out = content.slice(_offset, content.length);
    _i++;
    _offset = 0;
    return out;
  }
}
