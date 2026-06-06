import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import '../editing/commands.dart';
import '../editing/editor.dart';
import '../editing/input_rules.dart';
import '../editing/operations.dart';
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
  }

  final Editor _editor;

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
    _editor.dispose();
    super.dispose();
  }
}
