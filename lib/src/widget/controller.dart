import 'dart:async';
import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

import '../editing/commands.dart';
import '../editing/editor.dart';
import '../editing/input_rules.dart';
import '../editing/operations.dart';
import '../editing/search.dart';
import '../editing/transaction.dart';
import '../model/document.dart';
import '../model/document_text.dart';
import '../model/node.dart';
import '../model/position.dart';
import '../model/selection.dart';
import '../markdown/markdown.dart';
import '../markdown/slug.dart';
import 'clipboard.dart';
import 'drop.dart';

/// Which view the editor is presenting.
enum EditorMode {
  /// Rich, rendered editing.
  wysiwyg,

  /// Raw Markdown source editing.
  source,
}

/// A snapshot of document size metrics, suitable for a status bar.
@immutable
class DocumentStats {
  const DocumentStats({
    required this.words,
    required this.characters,
    required this.blocks,
  });

  /// Number of whitespace-delimited words across all text content.
  final int words;

  /// Number of characters (grapheme clusters) across all text content.
  final int characters;

  /// Number of top-level blocks in the document (text and non-text alike).
  final int blocks;

  @override
  bool operator ==(Object other) =>
      other is DocumentStats &&
      other.words == words &&
      other.characters == characters &&
      other.blocks == blocks;

  @override
  int get hashCode => Object.hash(words, characters, blocks);

  @override
  String toString() =>
      'DocumentStats(words: $words, characters: $characters, blocks: $blocks)';
}

/// One heading in a document [outline], suitable for a navigation pane.
@immutable
class OutlineEntry {
  const OutlineEntry({
    required this.level,
    required this.text,
    required this.nodeId,
  });

  /// Heading level, 1–6.
  final int level;

  /// The heading's plain text (inline formatting markers stripped).
  final String text;

  /// The id of the heading block, for scrolling/selecting it.
  final String nodeId;

  @override
  bool operator ==(Object other) =>
      other is OutlineEntry &&
      other.level == level &&
      other.text == text &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(level, text, nodeId);

  @override
  String toString() => 'OutlineEntry(h$level, "$text", $nodeId)';
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

  // Memoize whole-document serialization by document identity, so repeated
  // `markdown` reads (autosave listeners + onChanged + callers) don't
  // re-serialize. The document is immutable, so identity == content.
  Document? _serializedFor;
  String _serializedMd = '';

  /// The Markdown source. In source mode this reflects in-progress edits.
  String get markdown {
    if (_mode == EditorMode.source) return _sourceText;
    if (!identical(_serializedFor, document)) {
      _serializedFor = document;
      _serializedMd = Markdown.serialize(document);
    }
    return _serializedMd;
  }

  set markdown(String value) {
    if (_mode == EditorMode.source) {
      _sourceText = value;
    } else {
      _editor.setDocument(Markdown.parse(value));
    }
    notifyListeners();
  }

  /// Replaces the document directly (e.g. to seed plugin/custom blocks that
  /// aren't expressible as Markdown).
  void setDocument(Document document, {DocumentSelection? selection}) =>
      _editor.setDocument(document, selection: selection);

  // ── Mode switching (single source of truth) ──────────────────────────────

  void toggleMode() =>
      setMode(_mode == EditorMode.wysiwyg ? EditorMode.source : EditorMode.wysiwyg);

  void setMode(EditorMode mode) {
    if (mode == _mode) return;
    if (mode == EditorMode.source) {
      _sourceText = Markdown.serialize(document);
      final sel = selection;
      sourceCaret =
          sel != null ? markdownOffsetForPosition(sel.extent) : _sourceText.length;
      sourceCaretBase =
          sel != null ? markdownOffsetForPosition(sel.base) : sourceCaret;
    } else {
      _editor.setDocument(Markdown.parse(_sourceText));
      final extent = positionForMarkdownOffset(sourceCaret);
      final base = positionForMarkdownOffset(sourceCaretBase);
      if (extent != null) {
        _editor.setSelection(DocumentSelection(
          base: base ?? extent,
          extent: extent,
        ));
      }
    }
    _mode = mode;
    notifyListeners();
  }

  /// The source-text selection, preserved across WYSIWYG⇄source toggles.
  /// [sourceCaret] is the extent; [sourceCaretBase] the anchor.
  int sourceCaret = 0;
  int sourceCaretBase = 0;

  /// Records in-progress source-mode edits so a later [toggleMode] re-parses
  /// the latest text.
  void updateSourceText(String value) => _sourceText = value;

  /// The source-text caret offset corresponding to the current document
  /// selection's extent (for caret preservation when switching to source mode).
  int markdownOffsetForPosition(DocumentPosition pos) {
    final (_, starts) = Markdown.serializeWithOffsets(document);
    final start = starts[pos.nodeId];
    if (start == null) return 0;
    final node = document.nodeById(pos.nodeId);
    final np = pos.nodePosition;
    if (node is! TextBlockNode || np is! TextNodePosition) return start;
    final full = Markdown.serialize(Document([node]));
    final inlineFull = Markdown.deltaToInline(node.delta);
    final prefix = full.length - inlineFull.length; // block marker length
    final caret = np.offset.clamp(0, node.delta.length);
    final toCaret = Markdown.deltaToInline(node.delta.slice(0, caret)).length;
    return start + prefix + toCaret;
  }

  /// The document position corresponding to a source-text caret [offset] (for
  /// caret preservation when switching back from source mode).
  DocumentPosition? positionForMarkdownOffset(int offset) {
    final (_, starts) = Markdown.serializeWithOffsets(document);
    // The block whose start is the greatest one at or before [offset].
    String? bestId;
    var bestStart = -1;
    starts.forEach((id, s) {
      if (s <= offset && s > bestStart) {
        bestStart = s;
        bestId = id;
      }
    });
    if (bestId == null) return null;
    final node = document.nodeById(bestId!);
    if (node is! TextBlockNode) {
      return DocumentPosition.text(bestId!, 0);
    }
    final full = Markdown.serialize(Document([node]));
    final inlineFull = Markdown.deltaToInline(node.delta);
    final prefix = full.length - inlineFull.length;
    final rem = (offset - bestStart - prefix).clamp(0, inlineFull.length);
    // Invert deltaToInline: the largest caret whose encoded length fits in rem.
    var caret = 0;
    for (var c = 0; c <= node.delta.length; c++) {
      if (Markdown.deltaToInline(node.delta.slice(0, c)).length <= rem) {
        caret = c;
      } else {
        break;
      }
    }
    return DocumentPosition.text(bestId!, caret);
  }

  // ── Selection (one authority, expressed over the document text stream) ────

  void setSelection(DocumentSelection? selection) =>
      _editor.setSelection(selection);

  /// The unified document text stream + offset mapping for the current document
  /// (§13). The single coordinate system selection/IME/clipboard share.
  DocumentText documentText() => DocumentText.of(document);

  /// Collapses the selection (caret) at [pos].
  void placeCaretAt(DocumentPosition pos) =>
      setSelection(DocumentSelection.collapsed(pos));

  /// Extends the selection to [pos], keeping the current anchor (base). Falls
  /// back to a caret at [pos] when there is no current selection.
  void extendSelectionTo(DocumentPosition pos) {
    final sel = selection;
    setSelection(DocumentSelection(base: sel?.base ?? pos, extent: pos));
  }

  /// Selects the document-stream range `[base, extent]` (global offsets). This
  /// is the single entry point shared by gestures, IME, and keyboard.
  void selectByOffsets(int base, int extent) {
    final dt = documentText();
    if (!dt.coversAny) return;
    setSelection(dt.selectionOf(
      base.clamp(0, dt.text.length),
      extent.clamp(0, dt.text.length),
    ));
  }

  /// The current selection as a `(base, extent)` pair of stream offsets, or null
  /// when there is no selection / it isn't on the stream.
  (int, int)? selectionOffsets() {
    final sel = selection;
    if (sel == null) return null;
    final dt = documentText();
    if (!dt.covers(sel.base.nodeId) || !dt.covers(sel.extent.nodeId)) return null;
    return (dt.offsetOf(sel.base), dt.offsetOf(sel.extent));
  }

  /// Selects the entire document, from the start of the first text block to the
  /// end of the last text block. A no-op if there are no text blocks.
  void selectAll() {
    final nodes = document.nodes;
    TextBlockNode? first;
    TextBlockNode? last;
    for (final n in nodes) {
      if (n is TextBlockNode) {
        first ??= n;
        last = n;
      }
    }
    if (first == null || last == null) return;
    setSelection(DocumentSelection(
      base: DocumentPosition.text(first.id, 0),
      extent: DocumentPosition.text(last.id, last.delta.length),
    ));
  }

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

  /// Converts the active block into a GitHub-style callout/alert quote of
  /// [kind] (`note`, `tip`, `important`, `warning`, `caution`), preserving its
  /// text. A no-op if there is no active text block.
  void setCallout(String kind) {
    _canRevertRule = false;
    final sel = selection;
    if (sel == null) return;
    final node = document.nodeById(sel.extent.nodeId);
    if (node is! TextBlockNode) return;
    final index = document.indexOfId(node.id);
    final replacement =
        TextBlockNode.quote(id: node.id, delta: node.delta, callout: kind);
    _editor.apply(EditTransaction(
      operations: [ReplaceNodeOp(index, node, replacement)],
      selectionBefore: sel,
      selectionAfter: sel,
      tag: 'set-callout',
    ));
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

  /// Inserts an image block at the caret.
  void insertImage(String url, {String? alt}) =>
      _replaceActiveWithAtomic(ImageNode(url: url, alt: alt));

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

  // ── Drag & drop ──────────────────────────────────────────────────────────

  /// Inserts dropped [items] at the caret (or at [at], if given). Text items are
  /// smart-pasted as Markdown; image items become image blocks.
  void applyDrop(List<DroppedItem> items, {DocumentPosition? at}) {
    if (at != null) setSelection(DocumentSelection.collapsed(at));
    for (final item in items) {
      switch (item.kind) {
        case DropKind.text:
          pasteMarkdown(item.value);
        case DropKind.image:
          // Don't clobber existing text: drop the image onto its own line.
          final node = document.nodeById(selection?.extent.nodeId ?? '');
          if (node is TextBlockNode && node.delta.isNotEmpty) splitBlock();
          insertImage(item.value, alt: item.alt);
      }
    }
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

  /// Moves the block at index [from] so it lands at index [to] in the resulting
  /// document (one undo unit). No-op for equal or out-of-range indices.
  void reorderBlock(int from, int to) {
    _canRevertRule = false;
    final n = document.length;
    if (from < 0 || from >= n || from == to) return;
    final node = document.nodes[from];
    // After removing [from], the destination index in the shrunken list.
    final dest = to.clamp(0, n - 1);
    _editor.apply(EditTransaction(
      operations: [DeleteNodeOp(from, node), InsertNodeOp(dest, node)],
      selectionBefore: selection,
      selectionAfter: selection,
      tag: 'reorder-block',
    ));
  }

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

  /// Computes word, character and block counts for the current document.
  ///
  /// Words and characters are tallied across all text-bearing blocks
  /// (paragraphs, headings, list items, quotes, definitions, …) and table
  /// cells. Characters are counted as grapheme clusters. Blocks counts every
  /// top-level node, including non-text blocks like rules, images and diagrams.
  DocumentStats documentStats() {
    var words = 0;
    var characters = 0;
    void tally(String text) {
      characters += text.characters.length;
      words += text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    }

    for (final node in document.nodes) {
      if (node is TextBlockNode) {
        tally(node.delta.toPlainText());
      } else if (node is TableNode) {
        for (var r = 0; r < node.rowCount; r++) {
          for (var c = 0; c < node.columnCount; c++) {
            tally(node.cellText(r, c));
          }
        }
      }
    }
    return DocumentStats(
      words: words,
      characters: characters,
      blocks: document.nodes.length,
    );
  }

  /// Serializes the current document to semantic HTML.
  String toHtml() => Markdown.toHtml(document);

  // ── Clipboard ────────────────────────────────────────────────────────────

  /// The current selection as Markdown: inline Markdown for a single-block
  /// selection, or the serialized spanned structure for a cross-block one.
  /// Null when there is no (non-collapsed) selection.
  String? selectionMarkdown() {
    final sel = selection;
    if (sel == null || sel.isCollapsed) return null;
    if (sel.base.nodeId == sel.extent.nodeId) {
      final node = document.nodeById(sel.base.nodeId);
      if (node is! TextBlockNode) return null;
      final a = (sel.base.nodePosition as TextNodePosition).offset;
      final b = (sel.extent.nodePosition as TextNodePosition).offset;
      return Markdown.deltaToInline(
          node.delta.slice(math.min(a, b), math.max(a, b)));
    }
    final sub = _selectionSubDocument();
    return sub == null ? null : Markdown.serialize(sub);
  }

  /// The selection's plain text (newline-joined across blocks), or null.
  String? selectionText() {
    final sub = _selectionSubDocument();
    if (sub == null) return null;
    return sub.nodes
        .whereType<TextBlockNode>()
        .map((n) => n.delta.toPlainText())
        .join('\n');
  }

  /// Builds a [ClipboardPayload] for the current selection, or null when there
  /// is nothing selected.
  ClipboardPayload? selectionPayload() {
    final md = selectionMarkdown();
    if (md == null || md.isEmpty) return null;
    final sub = _selectionSubDocument();
    return ClipboardPayload(
      markdown: md,
      html: sub == null ? null : Markdown.toHtml(sub),
      plainText: selectionText(),
    );
  }

  /// Copies the current selection to [bridge] in all available flavors.
  Future<void> copy({ClipboardBridge bridge = const SystemClipboardBridge()}) async {
    final payload = selectionPayload();
    if (payload == null) return;
    await bridge.write(payload);
  }

  /// Copies the selection, then deletes it (one undo unit each).
  Future<void> cut({ClipboardBridge bridge = const SystemClipboardBridge()}) async {
    final sel = selection;
    if (sel == null || sel.isCollapsed) return;
    await copy(bridge: bridge);
    _canRevertRule = false;
    deleteBackward();
  }

  /// Reads [bridge] and pastes its best flavor (Markdown preferred) at the
  /// caret, replacing any selection.
  Future<void> paste({ClipboardBridge bridge = const SystemClipboardBridge()}) async {
    final payload = await bridge.read();
    if (payload == null) return;
    final md = (payload.markdown != null && payload.markdown!.isNotEmpty)
        ? payload.markdown
        : payload.plainText;
    if (md != null && md.isNotEmpty) pasteMarkdown(md);
  }

  /// Pastes the clipboard's text **literally** (no Markdown interpretation, no
  /// input rules) at the caret — "paste as plain text".
  Future<void> pastePlain(
      {ClipboardBridge bridge = const SystemClipboardBridge()}) async {
    final payload = await bridge.read();
    if (payload == null) return;
    final text = (payload.plainText != null && payload.plainText!.isNotEmpty)
        ? payload.plainText
        : payload.markdown;
    if (text == null || text.isEmpty) return;
    _canRevertRule = false;
    final txn = EditCommands.insertText(document, selection, text);
    if (txn != null) _editor.apply(txn);
  }

  /// The slice of the document covered by the current selection, as a new
  /// [Document], or null when nothing is selected.
  Document? _selectionSubDocument() {
    final sel = selection;
    if (sel == null || sel.isCollapsed) return null;
    final iBase = document.indexOfId(sel.base.nodeId);
    final iExt = document.indexOfId(sel.extent.nodeId);
    if (iBase < 0 || iExt < 0) return null;
    int offsetOf(DocumentPosition p) => p.nodePosition is TextNodePosition
        ? (p.nodePosition as TextNodePosition).offset
        : 0;
    if (iBase == iExt) {
      final node = document.nodes[iBase];
      if (node is! TextBlockNode) return null;
      final a = offsetOf(sel.base);
      final b = offsetOf(sel.extent);
      return Document(
          [node.copyWithDelta(node.delta.slice(math.min(a, b), math.max(a, b)))]);
    }
    final startIdx = math.min(iBase, iExt);
    final endIdx = math.max(iBase, iExt);
    final startPos = iBase <= iExt ? sel.base : sel.extent;
    final endPos = iBase <= iExt ? sel.extent : sel.base;
    final out = <Node>[];
    for (var idx = startIdx; idx <= endIdx; idx++) {
      final n = document.nodes[idx];
      if (n is TextBlockNode) {
        final from = idx == startIdx ? offsetOf(startPos) : 0;
        final to = idx == endIdx ? offsetOf(endPos) : n.delta.length;
        out.add(n.copyWithDelta(n.delta.slice(from, to)));
      } else {
        out.add(n); // include atomic nodes whole
      }
    }
    return Document(out);
  }

  /// Builds a nested Markdown table of contents linking to each heading's
  /// anchor slug (matching [toHtml]'s heading ids). Returns an empty string
  /// when the document has no headings.
  String tableOfContents() {
    final entries = outline();
    if (entries.isEmpty) return '';
    final minLevel = entries.map((e) => e.level).reduce(math.min);
    final slugs = SlugAllocator();
    final lines = <String>[];
    for (final e in entries) {
      final indent = '  ' * (e.level - minLevel);
      final slug = slugs.allocate(slugify(e.text));
      lines.add('$indent- [${e.text}](#$slug)');
    }
    return lines.join('\n');
  }

  /// Returns the document's headings in order as an [OutlineEntry] list,
  /// suitable for a table-of-contents / navigation pane.
  List<OutlineEntry> outline() {
    final entries = <OutlineEntry>[];
    for (final node in document.nodes) {
      if (node is TextBlockNode &&
          node.type == BlockType.heading &&
          node.level != null) {
        entries.add(OutlineEntry(
          level: node.level!,
          text: node.delta.toPlainText(),
          nodeId: node.id,
        ));
      }
    }
    return entries;
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
