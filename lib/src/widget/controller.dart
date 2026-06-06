import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import '../editing/commands.dart';
import '../editing/editor.dart';
import '../editing/input_rules.dart';
import '../editing/operations.dart';
import '../editing/search.dart';
import '../editing/transaction.dart';
import '../model/document.dart';
import '../model/node.dart';
import '../model/position.dart';
import '../model/selection.dart';
import '../markdown/markdown.dart';

/// Which view the editor is presenting.
enum EditorMode {
  /// Rich, rendered editing.
  wysiwyg,

  /// Raw Markdown source editing.
  source,
}

/// The public controller for [MarkdownEditor].
///
/// Owns the editing [Editor] and exposes Markdown as the source of truth, the
/// current mode, and high-level editing intents (which route through the same
/// command pipeline the UI uses). Listen to it for changes (e.g. autosave).
class MarkdownEditorController extends ChangeNotifier {
  MarkdownEditorController({String? markdown, List<InputRule>? inputRules})
      : _editor = Editor(
          document: markdown != null && markdown.isNotEmpty
              ? Markdown.parse(markdown)
              : Document.empty(),
        ),
        inputRules = inputRules ?? defaultInputRules {
    _editor.addListener(_onEditorChanged);
    _editor.onLocalApply = _outgoing.add;
  }

  final Editor _editor;

  /// Transactions applied locally, for a collaboration layer to broadcast.
  /// Synchronous so peers stay in lockstep within a frame.
  final StreamController<EditTransaction> _outgoing =
      StreamController<EditTransaction>.broadcast(sync: true);

  /// Stream of locally-applied transactions (see [CollaborationSession]).
  Stream<EditTransaction> get outgoing => _outgoing.stream;

  /// Applies a transaction received from a remote peer (no local undo entry,
  /// no re-broadcast).
  void applyRemote(EditTransaction txn) => _editor.applyRemote(txn);

  /// The ordered input rules applied on text insertion.
  List<InputRule> inputRules;

  EditorMode _mode = EditorMode.wysiwyg;
  String _sourceText = '';

  /// True immediately after an input rule fired, so the next backspace reverts
  /// the auto-transform instead of deleting (ProseMirror `undoInputRule`).
  bool _canRevertRule = false;

  void _onEditorChanged() => notifyListeners();

  // ── State accessors ──────────────────────────────────────────────────────

  Document get document => _editor.document;
  DocumentSelection? get selection => _editor.selection;
  EditorMode get mode => _mode;
  bool get canUndo => _editor.canUndo;
  bool get canRedo => _editor.canRedo;

  /// The Markdown source. In source mode this reflects in-progress edits.
  String get markdown =>
      _mode == EditorMode.source ? _sourceText : Markdown.serialize(document);

  set markdown(String value) {
    if (_mode == EditorMode.source) {
      _sourceText = value;
    } else {
      _editor.setDocument(Markdown.parse(value));
    }
    notifyListeners();
  }

  // ── Mode switching (single source of truth) ──────────────────────────────

  void toggleMode() =>
      setMode(_mode == EditorMode.wysiwyg ? EditorMode.source : EditorMode.wysiwyg);

  void setMode(EditorMode mode) {
    if (mode == _mode) return;
    if (mode == EditorMode.source) {
      _sourceText = Markdown.serialize(document);
    } else {
      _editor.setDocument(Markdown.parse(_sourceText));
    }
    _mode = mode;
    notifyListeners();
  }

  /// Records in-progress source-mode edits so a later [toggleMode] re-parses
  /// the latest text.
  void updateSourceText(String value) => _sourceText = value;

  // ── Selection ────────────────────────────────────────────────────────────

  void setSelection(DocumentSelection? selection) =>
      _editor.setSelection(selection);

  // ── Editing intents (route through the command pipeline) ─────────────────

  /// Inserts [text] at the caret (replacing any selection), then applies input
  /// rules. If a rule fires, arms the backspace-revert.
  void insertText(String text) {
    _canRevertRule = false;
    final txn = EditCommands.insertText(document, selection, text);
    if (txn == null) return;
    _editor.apply(txn);
    final rule = applyInputRules(document, selection, rules: inputRules);
    if (rule != null) {
      _editor.apply(rule);
      _canRevertRule = true; // the rule txn is now top of the undo stack
    }
  }

  void deleteBackward() {
    if (_canRevertRule) {
      _canRevertRule = false;
      _editor.undo(); // revert the just-applied input rule as one unit
      return;
    }
    final txn = EditCommands.deleteBackward(document, selection);
    if (txn != null) _editor.apply(txn);
  }

  void splitBlock() {
    _canRevertRule = false;
    final txn = EditCommands.splitBlock(document, selection);
    if (txn != null) _editor.apply(txn);
  }

  void toggleMark(String key) {
    _canRevertRule = false;
    final txn = EditCommands.toggleMark(document, selection, key);
    if (txn != null) _editor.apply(txn);
  }

  void setBlockType(String type, {int? level}) {
    _canRevertRule = false;
    final txn = EditCommands.setBlockType(document, selection, type, level: level);
    if (txn != null) _editor.apply(txn);
  }

  /// Toggles the checked state of the task-list item with [nodeId].
  void toggleTodo(String nodeId) {
    _canRevertRule = false;
    final txn = EditCommands.toggleTodo(document, nodeId, selection);
    if (txn != null) _editor.apply(txn);
  }

  /// Replaces the active block with a thematic break, adding a trailing
  /// paragraph for the caret.
  void insertDivider() => _replaceActiveWithAtomic(HorizontalRuleNode());

  /// Replaces the active block with an (empty) code block, adding a trailing
  /// paragraph for the caret.
  void insertCodeBlock() => _replaceActiveWithAtomic(CodeBlockNode(code: ''));

  void _replaceActiveWithAtomic(Node atomic) {
    _canRevertRule = false;
    final sel = selection;
    if (sel == null) return;
    final node = document.nodeById(sel.extent.nodeId);
    if (node == null) return;
    final index = document.indexOfId(node.id);
    final para = TextBlockNode.paragraph();
    _editor.apply(EditTransaction(
      operations: [
        ReplaceNodeOp(index, node, atomic),
        InsertNodeOp(index + 1, para),
      ],
      selectionBefore: sel,
      selectionAfter:
          DocumentSelection.collapsed(DocumentPosition.text(para.id, 0)),
      tag: 'insert-block',
    ));
  }

  // ── Smart paste ──────────────────────────────────────────────────────────

  /// Parses [markdown] and inserts the resulting content at the caret. A single
  /// paragraph merges inline (preserving marks); multi-block content splits the
  /// current block and inserts the parsed blocks between the halves.
  void pasteMarkdown(String markdown) {
    if (markdown.isEmpty) return;
    final sel = selection;
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return;
    final node = document.nodeById(sel.extent.nodeId);
    if (node is! TextBlockNode) return;
    final basePos = sel.base.nodePosition;
    final extPos = sel.extent.nodePosition;
    if (basePos is! TextNodePosition || extPos is! TextNodePosition) return;
    final len = node.delta.length;
    final start =
        (basePos.offset < extPos.offset ? basePos.offset : extPos.offset)
            .clamp(0, len);
    final end = (basePos.offset < extPos.offset ? extPos.offset : basePos.offset)
        .clamp(0, len);
    final index = document.indexOfId(node.id);

    final parsed = Markdown.parse(markdown).nodes;
    _canRevertRule = false;

    // Inline fast path: a single paragraph merges into the current block.
    if (parsed.length == 1 &&
        parsed.first is TextBlockNode &&
        (parsed.first as TextBlockNode).type == BlockType.paragraph) {
      final ins = (parsed.first as TextBlockNode).delta;
      final merged = node.delta
          .slice(0, start)
          .concat(ins)
          .concat(node.delta.slice(end, node.delta.length));
      _editor.apply(EditTransaction(
        operations: [ReplaceNodeOp(index, node, node.copyWithDelta(merged))],
        selectionBefore: sel,
        selectionAfter: DocumentSelection.collapsed(
            DocumentPosition.text(node.id, start + ins.length)),
        tag: 'paste',
      ));
      return;
    }

    // Multi-block paste: split the current block and insert parsed blocks.
    final left = node.copyWithDelta(node.delta.slice(0, start));
    final rightDelta = node.delta.slice(end, node.delta.length);
    final right = TextBlockNode.paragraph(delta: rightDelta);
    final ops = <Operation>[ReplaceNodeOp(index, node, left)];
    var at = index + 1;
    for (final n in parsed) {
      ops.add(InsertNodeOp(at, n));
      at++;
    }
    ops.add(InsertNodeOp(at, right));
    _editor.apply(EditTransaction(
      operations: ops,
      selectionBefore: sel,
      selectionAfter: DocumentSelection.collapsed(DocumentPosition.text(right.id, 0)),
      tag: 'paste',
    ));
  }

  // ── Block reordering ─────────────────────────────────────────────────────

  void moveBlockUp(String nodeId) => _moveBlock(nodeId, -1);
  void moveBlockDown(String nodeId) => _moveBlock(nodeId, 1);

  void _moveBlock(String nodeId, int dir) {
    _canRevertRule = false;
    final i = document.indexOfId(nodeId);
    if (i < 0) return;
    final target = i + dir;
    if (target < 0 || target >= document.length) return;
    final node = document.nodes[i];
    _editor.apply(EditTransaction(
      operations: [DeleteNodeOp(i, node), InsertNodeOp(target, node)],
      selectionBefore: selection,
      selectionAfter: selection,
      tag: 'move-block',
    ));
  }

  // ── Table editing ────────────────────────────────────────────────────────

  void _applyTable(String tableId, TableNode Function(TableNode) update) {
    _canRevertRule = false;
    final node = document.nodeById(tableId);
    if (node is! TableNode) return;
    _editor.apply(EditTransaction(
      operations: [ReplaceNodeOp(document.indexOfId(tableId), node, update(node))],
      selectionBefore: selection,
      selectionAfter: selection,
      tag: 'table-edit',
    ));
  }

  /// Sets a table cell's content from an inline-Markdown string (so formatting
  /// like `**bold**` and `[links](…)` round-trips).
  void updateTableCell(String tableId, int row, int col, String markdown) =>
      _applyTable(
          tableId, (t) => t.withCell(row, col, Markdown.inlineToDelta(markdown)));

  /// The inline-Markdown source of a table cell (for editing).
  String cellMarkdown(String tableId, int row, int col) {
    final node = document.nodeById(tableId);
    if (node is! TableNode) return '';
    return Markdown.deltaToInline(node.rows[row][col]);
  }

  /// Appends an empty row to a table.
  void addTableRow(String tableId) =>
      _applyTable(tableId, (t) => t.withAppendedRow());

  /// Appends an empty column to a table.
  void addTableColumn(String tableId) =>
      _applyTable(tableId, (t) => t.withAppendedColumn());

  // ── Find & replace ───────────────────────────────────────────────────────

  /// All occurrences of [query] across the document, in order.
  List<MatchLocation> findMatches(String query, {bool caseSensitive = false}) =>
      findInDocument(document, query, caseSensitive: caseSensitive);

  /// Selects [m] (so it's visible/highlighted).
  void selectMatch(MatchLocation m) {
    setSelection(DocumentSelection(
      base: DocumentPosition.text(m.nodeId, m.start),
      extent: DocumentPosition.text(m.nodeId, m.end),
    ));
  }

  /// Replaces a single match with [replacement].
  void replaceMatch(MatchLocation m, String replacement) {
    _canRevertRule = false;
    final node = document.nodeById(m.nodeId);
    if (node is! TextBlockNode) return;
    final index = document.indexOfId(node.id);
    final attrs = m.start > 0 ? node.delta.attributesAt(m.start) : const <String, Object?>{};
    final newDelta =
        node.delta.delete(m.start, m.end).insert(m.start, replacement, attrs);
    _editor.apply(EditTransaction(
      operations: [ReplaceNodeOp(index, node, node.copyWithDelta(newDelta))],
      selectionBefore: selection,
      selectionAfter: DocumentSelection.collapsed(
          DocumentPosition.text(node.id, m.start + replacement.length)),
      tag: 'replace',
    ));
  }

  /// Replaces every occurrence of [query] with [replacement] as one undo unit.
  void replaceAll(String query, String replacement, {bool caseSensitive = false}) {
    if (query.isEmpty) return;
    _canRevertRule = false;
    final ops = <Operation>[];
    for (final node in document.nodes) {
      if (node is! TextBlockNode) continue;
      // Replace right-to-left so earlier offsets stay valid.
      final matches = findInDocument(Document([node]), query,
          caseSensitive: caseSensitive);
      if (matches.isEmpty) continue;
      var delta = node.delta;
      for (final m in matches.reversed) {
        final attrs = m.start > 0 ? delta.attributesAt(m.start) : const <String, Object?>{};
        delta = delta.delete(m.start, m.end).insert(m.start, replacement, attrs);
      }
      ops.add(ReplaceNodeOp(
          document.indexOfId(node.id), node, node.copyWithDelta(delta)));
    }
    if (ops.isEmpty) return;
    _editor.apply(EditTransaction(
      operations: ops,
      selectionBefore: selection,
      selectionAfter: selection,
      tag: 'replace-all',
    ));
  }

  void undo() {
    _canRevertRule = false;
    _editor.undo();
  }

  void redo() {
    _canRevertRule = false;
    _editor.redo();
  }

  // ── Caret movement (grapheme-aware, crossing blocks) ─────────────────────

  void moveCaretLeft() => _moveCaret(forward: false);
  void moveCaretRight() => _moveCaret(forward: true);

  void _moveCaret({required bool forward}) {
    _canRevertRule = false;
    final sel = selection;
    if (sel == null) return;
    final node = document.nodeById(sel.extent.nodeId);
    if (node is! TextBlockNode) return;
    final pos = sel.extent.nodePosition;
    if (pos is! TextNodePosition) return;

    if (!sel.isCollapsed) {
      final a = (sel.base.nodePosition as TextNodePosition).offset;
      final b = pos.offset;
      final edge = forward ? (a > b ? a : b) : (a < b ? a : b);
      setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(node.id, edge),
      ));
      return;
    }

    final plain = node.delta.toPlainText();
    final offset = pos.offset;
    if (forward) {
      if (offset < plain.length) {
        final next =
            plain.characters.take(offset).string.length; // current cluster start
        final advanced = _graphemeAfter(plain, offset);
        setSelection(DocumentSelection.collapsed(
          DocumentPosition.text(node.id, advanced == offset ? next : advanced),
        ));
      } else {
        final after = document.nodeAfter(node.id);
        if (after is TextBlockNode) {
          setSelection(DocumentSelection.collapsed(
            DocumentPosition.text(after.id, 0),
          ));
        }
      }
    } else {
      if (offset > 0) {
        final before = plain.substring(0, offset).characters.skipLast(1).string.length;
        setSelection(DocumentSelection.collapsed(
          DocumentPosition.text(node.id, before),
        ));
      } else {
        final prev = document.nodeBefore(node.id);
        if (prev is TextBlockNode) {
          setSelection(DocumentSelection.collapsed(
            DocumentPosition.text(prev.id, prev.delta.length),
          ));
        }
      }
    }
  }

  static int _graphemeAfter(String text, int offset) {
    final range = text.characters.iterator;
    var pos = 0;
    while (range.moveNext()) {
      final clusterLen = range.current.length;
      if (pos == offset) return pos + clusterLen;
      pos += clusterLen;
      if (pos > offset) return pos;
    }
    return text.length;
  }

  @override
  void dispose() {
    _editor.removeListener(_onEditorChanged);
    _outgoing.close();
    _editor.dispose();
    super.dispose();
  }
}
