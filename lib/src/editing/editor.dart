import 'package:flutter/foundation.dart';

import '../model/document.dart';
import '../model/selection.dart';
import 'transaction.dart';

/// The editing engine: holds the current [document] and [selection], applies
/// [EditTransaction]s, and maintains undo/redo history.
///
/// Undo uses inverse operations (not snapshot-replay): each applied transaction
/// is pushed to the undo stack, and undo applies its [EditTransaction.inverse].
/// Consecutive transactions with the same mergeable [EditTransaction.tag]
/// (e.g. `'typing'`) coalesce into one undo unit within [_mergeWindow].
class Editor extends ChangeNotifier {
  Editor({Document? document, DocumentSelection? selection})
      : _document = document ?? Document.empty(),
        _selection = selection;

  Document _document;
  DocumentSelection? _selection;

  final List<EditTransaction> _undo = [];
  final List<EditTransaction> _redo = [];
  DateTime _lastEditTime = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _mergeWindow = Duration(milliseconds: 600);

  /// Tags that may coalesce into a single undo unit while typed rapidly.
  static const Set<String> _mergeableTags = {'typing'};

  Document get document => _document;
  DocumentSelection? get selection => _selection;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Applies [txn], updates the selection, and records it for undo.
  void apply(EditTransaction txn) {
    if (txn.isEmpty && txn.selectionAfter == null) return;
    _document = txn.apply(_document);
    _selection = txn.selectionAfter ?? _selection;

    if (!txn.isEmpty) {
      final now = DateTime.now();
      final mergeable = txn.tag != null && _mergeableTags.contains(txn.tag);
      if (mergeable &&
          _undo.isNotEmpty &&
          _undo.last.tag == txn.tag &&
          now.difference(_lastEditTime) <= _mergeWindow) {
        // Coalesce: keep the original selectionBefore, extend ops.
        final prev = _undo.removeLast();
        _undo.add(EditTransaction(
          operations: [...prev.operations, ...txn.operations],
          selectionBefore: prev.selectionBefore,
          selectionAfter: txn.selectionAfter,
          tag: txn.tag,
        ));
      } else {
        _undo.add(txn);
      }
      _redo.clear();
      _lastEditTime = now;
    }
    notifyListeners();
  }

  /// Sets the selection without recording an undo entry.
  void setSelection(DocumentSelection? selection) {
    if (_selection == selection) return;
    _selection = selection;
    notifyListeners();
  }

  /// Replaces the entire document (e.g. after editing in source mode). Clears
  /// history because offsets no longer correspond.
  void setDocument(Document document, {DocumentSelection? selection}) {
    _document = document;
    _selection = selection;
    _undo.clear();
    _redo.clear();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final txn = _undo.removeLast();
    final inverse = txn.inverse();
    _document = inverse.apply(_document);
    _selection = inverse.selectionAfter;
    _redo.add(txn);
    _lastEditTime = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final txn = _redo.removeLast();
    _document = txn.apply(_document);
    _selection = txn.selectionAfter;
    _undo.add(txn);
    _lastEditTime = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
  }
}
