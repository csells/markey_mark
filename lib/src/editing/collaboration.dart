import 'dart:async';

import '../widget/controller.dart';

/// Connects multiple [MarkdownEditorController]s so edits on one are applied to
/// the others in real time — the collaboration seam over the operation log.
///
/// This is the in-process foundation: it broadcasts each locally-applied
/// transaction to peers (who apply it without re-broadcasting). A network
/// transport plugs in here by serializing the transactions between processes.
///
/// Non-conflicting edits (different blocks, or turn-taking) stay consistent.
/// Genuinely *concurrent conflicting* edits need operational transform or a
/// CRDT layered on the same op log (future work) — the architecture is designed
/// to allow that without changing the editing core.
class CollaborationSession {
  CollaborationSession(List<MarkdownEditorController> peers)
      : _peers = List.unmodifiable(peers) {
    for (final source in _peers) {
      _subs.add(source.outgoing.listen((txn) {
        for (final target in _peers) {
          if (!identical(target, source)) target.applyRemote(txn);
        }
      }));
    }
  }

  final List<MarkdownEditorController> _peers;
  final List<StreamSubscription<void>> _subs = [];
  bool _disposed = false;

  List<MarkdownEditorController> get peers => _peers;
  bool get isActive => !_disposed;

  /// Stops syncing (cancels all subscriptions). Does not dispose the peers.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}
