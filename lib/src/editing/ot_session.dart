import 'dart:async';

import '../widget/controller.dart';
import 'ot.dart';
import 'transaction.dart';

/// A **convergent** in-process collaboration session: peers may edit
/// concurrently (while delivery is buffered), and once [flush]ed they converge
/// to the same document via operational transformation — the OT layer wired into
/// the runtime `applyRemote` path (the raw, non-transforming path would diverge).
///
/// Model (Jupiter-style with a single relay that totally-orders ops):
/// - Each peer applies its local edits optimistically and the session records
///   them as that peer's *pending* (un-acknowledged) ops.
/// - [flush] sequences the buffered ops into a canonical [_log]. Each op is
///   **server-transformed** against the canonical ops the sender hadn't seen
///   (skipping the sender's own causally-prior ops), then delivered to every
///   other peer **client-transformed** against that peer's pending ops (which
///   are themselves rebased), and acknowledged to the sender.
/// - Same-target conflicts (two concurrent edits of the *same* block) resolve
///   deterministically by site id (last-writer-wins) so every peer agrees;
///   different-block edits merge losslessly. (Character-level intra-block merge
///   would need a Delta OT — tracked as future work.)
///
/// A real network transport drives [flush] on receive; the buffering makes the
/// concurrency deterministically testable.
class OtCollaborationSession {
  OtCollaborationSession(List<MarkdownEditorController> peers) {
    for (var i = 0; i < peers.length; i++) {
      // Site ids order conflicts deterministically (A < B < …).
      final state = _Peer(peers[i], String.fromCharCode(0x41 + i));
      _peers.add(state);
      _subs.add(peers[i].outgoing.listen((txn) => _onLocal(state, txn)));
    }
  }

  final List<_Peer> _peers = [];
  final List<StreamSubscription<EditTransaction>> _subs = [];
  final List<EditTransaction> _queueTxn = [];
  final List<_Peer> _queueSender = [];
  final List<int> _queueBase = [];
  final List<_Entry> _log = [];
  bool _disposed = false;

  List<MarkdownEditorController> get peers =>
      [for (final p in _peers) p.controller];
  bool get isActive => !_disposed;

  void _onLocal(_Peer sender, EditTransaction txn) {
    if (txn.isEmpty) return;
    sender.pending.add(txn);
    _queueTxn.add(txn);
    _queueSender.add(sender);
    _queueBase.add(sender.integrated); // canonical ops the sender had seen
  }

  /// Delivers all buffered ops to every peer with operational transformation,
  /// converging the documents.
  void flush() {
    while (_queueTxn.isNotEmpty) {
      final txn = _queueTxn.removeAt(0);
      final sender = _queueSender.removeAt(0);
      final base = _queueBase.removeAt(0);

      // Server transform against concurrent canonical ops (the sender's own
      // earlier ops are causally prior, not concurrent — skip them).
      var t = txn;
      for (var i = base; i < _log.length; i++) {
        if (_log[i].site == sender.site) continue;
        t = transformTransaction(t, _log[i].txn,
            tieBreak: _wins(sender.site, _log[i].site));
      }
      _log.add(_Entry(t, sender.site));

      for (final p in _peers) {
        if (identical(p, sender)) {
          if (p.pending.isNotEmpty) p.pending.removeAt(0); // ack
          p.integrated++;
          continue;
        }
        // Client transform: rebase the incoming op against this peer's pending
        // (optimistically-applied, un-acknowledged) ops, and rebase those too.
        var incoming = t;
        for (var j = 0; j < p.pending.length; j++) {
          final pend = p.pending[j];
          final next = transformTransaction(incoming, pend,
              tieBreak: _wins(sender.site, p.site));
          p.pending[j] = transformTransaction(pend, incoming,
              tieBreak: _wins(p.site, sender.site));
          incoming = next;
        }
        p.controller.applyRemote(incoming);
        p.integrated++;
      }
    }
  }

  /// Deterministic conflict winner: the larger site id wins a same-target clash.
  static bool _wins(String a, String b) => a.compareTo(b) > 0;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

class _Peer {
  _Peer(this.controller, this.site);
  final MarkdownEditorController controller;
  final String site;

  /// Locally-applied transactions not yet acknowledged by the relay.
  final List<EditTransaction> pending = [];

  /// Count of canonical ops this peer has integrated (applied or acked).
  int integrated = 0;
}

class _Entry {
  _Entry(this.txn, this.site);
  final EditTransaction txn;
  final String site;
}
