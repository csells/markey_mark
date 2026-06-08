import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:super_clipboard/super_clipboard.dart' as sc;
import 'package:super_drag_and_drop/super_drag_and_drop.dart' as sdd;

import '../editing/caret_motor.dart';
import '../editing/search.dart';
import '../model/attributes.dart';
import '../model/delta.dart';
import '../model/document.dart';
import '../model/document_text.dart';
import '../model/node.dart';
import '../model/position.dart';
import '../model/selection.dart';
import '../render/bidi.dart';
import '../render/code_highlight.dart';
import '../render/code_layout.dart';
import '../render/delta_text.dart';
import '../render/diagram_renderer.dart';
import '../render/markdown_source_highlight.dart';
import '../theme/editor_style.dart';
import '../ui/slash_menu.dart';
import 'block_registry.dart';
import 'clipboard.dart';
import 'controller.dart';
import 'drop.dart';
import 'ime_delta.dart';

/// A native, cross-platform WYSIWYG Markdown editor widget.
///
/// Renders [MarkdownEditorController.document] richly (WYSIWYG) or as raw
/// Markdown (source mode), with an optional formatting toolbar. 100% native
/// Flutter — no WebView, no JavaScript.
class MarkdownEditor extends StatefulWidget {
  const MarkdownEditor({
    super.key,
    required this.controller,
    this.style,
    this.showToolbar = true,
    this.readOnly = false,
    this.focusNode,
    this.slashItems,
    this.diagramRenderer = const NativeDiagramRenderer(),
    this.onChanged,
    this.clipboard = const SystemClipboardBridge(),
    this.enableDrop = true,
    this.placeholder,
    this.blockRegistry,
  });

  final MarkdownEditorController controller;
  final EditorStyle? style;
  final bool showToolbar;
  final bool readOnly;
  final FocusNode? focusNode;

  /// Slash (`/`) command-menu items. Defaults to [defaultSlashItems].
  final List<SlashMenuItem>? slashItems;

  /// Renders Mermaid diagrams. Defaults to a native source card.
  final DiagramRenderer diagramRenderer;

  /// Called with the document's Markdown whenever the content changes (not on
  /// selection-only changes). Convenient for autosave.
  final ValueChanged<String>? onChanged;

  /// The system-clipboard bridge used by copy/cut/paste. Defaults to the
  /// plain-text [SystemClipboardBridge]; pass a [SuperClipboardBridge] for
  /// rich multi-flavor OS clipboard support.
  final ClipboardBridge clipboard;

  /// Whether to accept OS drag-and-drop of text/images (native
  /// `super_drag_and_drop`, no JavaScript). On by default; read-only editors
  /// never accept drops.
  final bool enableDrop;

  /// Hint text shown over an empty document until the user types.
  final String? placeholder;

  /// Optional registry of renderers for custom/plugin block types
  /// ([CustomBlockNode]). The open block-set extension point (§13.5).
  final BlockRegistry? blockRegistry;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor>
    implements DeltaTextInputClient {
  late FocusNode _focusNode;
  final _MarkdownSourceController _sourceController = _MarkdownSourceController();
  final ValueNotifier<bool> _caretBlink = ValueNotifier<bool>(false);
  Timer? _blinkTimer;

  TextInputConnection? _connection;
  TextEditingValue _imeValue = TextEditingValue.empty;

  /// The active IME composing region (CJK/autocorrect), reflected back so the
  /// platform keeps composition alive across model syncs.
  TextRange _composing = TextRange.empty;

  /// Per-block laid-out text, keyed by node id (see [_layoutFor]).
  final Map<String, _CachedLayout> _layoutCache = {};

  /// Per-code-block line layouts, keyed by node id (see [_codeLayoutFor]). Kept
  /// separate from [_layoutCache] because code blocks lay out per-line so a
  /// keystroke re-shapes only the changed line, not the whole block.
  final Map<String, CodeLayout> _codeLayoutCache = {};

  /// Per-block paint-area keys, used to hit-test which block a drag is over so
  /// selection can extend across blocks.
  final Map<String, GlobalKey> _paintKeys = {};

  GlobalKey _paintKeyFor(String id) =>
      _paintKeys.putIfAbsent(id, () => GlobalKey());

  /// Right-click / long-press context menu (native AdaptiveTextSelectionToolbar).
  final ContextMenuController _contextMenu = ContextMenuController();

  /// True while a primary mouse button is held for a text drag-selection. While
  /// set, the document scroll view is frozen so the drag selects (across blocks)
  /// instead of scrolling.
  bool _mouseSelecting = false;

  /// Tracks WYSIWYG⇄source transitions so the source caret can be restored once.
  EditorMode? _lastMode;
  bool _enterSourcePending = false;

  /// Native code highlighter for code blocks (no WebView/JS).
  final CodeHighlighter _highlighter = const DefaultCodeHighlighter();

  // Find & replace bar state.
  bool _showFind = false;
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  List<MatchLocation> _matches = const [];
  int _matchIndex = -1;

  /// True after Escape dismisses the slash menu, until the `/` query is cleared.
  bool _slashSuppressed = false;
  static final RegExp _slashPattern = RegExp(r'^/(\S*)$');

  List<SlashMenuItem> get _slashItems => widget.slashItems ?? defaultSlashItems;

  MarkdownEditorController get _c => widget.controller;

  // Resolved-style memo. `EditorStyle.fromTheme` builds a fresh instance with no
  // value-equality, so calling it per frame would mint a new identity every
  // time and silently defeat every layout cache (which keys on a style
  // version). Cache the resolved style and bump [_styleVer] only when the
  // inputs (the explicit widget style or the ambient theme) actually change.
  EditorStyle? _cachedStyle;
  EditorStyle? _styleForWidget;
  ThemeData? _styleForTheme;
  int _styleVer = 0;

  EditorStyle _resolveStyle() {
    final theme = Theme.of(context);
    if (_cachedStyle == null ||
        _styleForWidget != widget.style ||
        _styleForTheme != theme) {
      _cachedStyle = widget.style ?? EditorStyle.fromTheme(theme);
      _styleForWidget = widget.style;
      _styleForTheme = theme;
      _styleVer++;
    }
    return _cachedStyle!;
  }

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _lastDoc = _c.document;
    _lastMode = _c.mode;
    _c.addListener(_onControllerChanged);
    _sourceController.addListener(_onSourceSelectionChanged);
  }

  /// Keep the controller's preserved source caret in sync with the source field.
  void _onSourceSelectionChanged() {
    if (_c.mode != EditorMode.source) return;
    final sel = _sourceController.selection;
    if (sel.isValid) {
      _c.sourceCaretBase = sel.baseOffset;
      _c.sourceCaret = sel.extentOffset;
    }
  }

  @override
  void dispose() {
    _stopBlink();
    _caretBlink.dispose();
    _c.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _focusNode.dispose();
    _sourceController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _connection?.close();
    _hideContextMenu();
    _handlesEntry?.remove();
    _handlesEntry = null;
    _sourceController.removeListener(_onSourceSelectionChanged);
    _disposeLayoutCache();
    super.dispose();
  }

  Object? _lastDoc;

  /// The horizontal "goal column" (block-local x, in logical px) preserved
  /// across a run of consecutive vertical (up/down) caret moves, mirroring
  /// Flutter's `VerticalCaretMovementRun`. Null when not in a vertical run; it
  /// resets on any other caret change (typing, click, horizontal/word move).
  double? _verticalGoalX;

  /// Set while applying a vertical move so [_onControllerChanged] doesn't reset
  /// the goal column for the selection change the move itself causes.
  bool _verticalMoving = false;

  /// The most recent painted block content width, used to lay out an adjacent
  /// (possibly not-yet-cached) block when moving the caret into it.
  double _lastBlockWidth = 0;

  void _onControllerChanged() {
    // Any caret change that isn't itself a vertical move ends the vertical run.
    if (!_verticalMoving) _verticalGoalX = null;
    // Fire onChanged only when the (immutable) document actually changed.
    if (widget.onChanged != null && !identical(_lastDoc, _c.document)) {
      _lastDoc = _c.document;
      widget.onChanged!(_c.markdown);
    }
    // On entering source mode, restore the caret once (see _buildSource).
    if (_lastMode != _c.mode) {
      if (_c.mode == EditorMode.source) _enterSourcePending = true;
      _lastMode = _c.mode;
    }
    // Re-arm the slash menu once the `/` query is gone.
    if (_activeSlashQuery() == null) _slashSuppressed = false;
    if (mounted) setState(_syncImeFromModel);
    // Touch handles follow the selection (post-frame, so paint keys resolve).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncSelectionHandles());
  }

  /// The slash-menu query if the focused active block is a paragraph matching
  /// `^/(\S*)$`, else null.
  String? _activeSlashQuery() {
    if (!_focusNode.hasFocus || widget.readOnly) return null;
    final block = _activeBlock;
    if (block == null || block.type != BlockType.paragraph) return null;
    return _slashPattern.firstMatch(block.delta.toPlainText())?.group(1);
  }

  /// True when there's a non-collapsed selection within a single focused block
  /// (the condition for showing the bubble toolbar).
  bool _hasRangeSelection() {
    if (!_focusNode.hasFocus || widget.readOnly) return false;
    final sel = _c.selection;
    if (sel == null || sel.isCollapsed) return false;
    return sel.base.nodeId == sel.extent.nodeId;
  }

  void _selectSlash(SlashMenuItem item) {
    final block = _activeBlock;
    if (block == null) return;
    // Clear the typed `/query`, then apply the command to the empty block.
    _c.setSelection(DocumentSelection(
      base: DocumentPosition.text(block.id, 0),
      extent: DocumentPosition.text(block.id, block.delta.length),
    ));
    _c.deleteBackward();
    item.apply(_c);
    setState(() => _slashSuppressed = true);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _openConnection();
      _startBlink();
    } else {
      _closeConnection();
      _stopBlink();
    }
    if (mounted) setState(() {});
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncSelectionHandles());
  }

  // ── Caret blink (only runs while focused — no idle CPU/timer otherwise) ───

  void _startBlink() {
    if (_blinkTimer != null) return;
    _caretBlink.value = true;
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 530), (_) {
      _caretBlink.value = !_caretBlink.value;
    });
  }

  void _stopBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _caretBlink.value = false;
  }

  // ── Per-block text-layout cache (avoid re-shaping unchanged text) ─────────

  /// Returns a laid-out [TextPainter] for a text [node] at [width], reusing the
  /// cache unless the block's (immutable) delta or the width changed. Text
  /// shaping is the dominant cost; this keeps a steady-state edit to one layout
  /// per frame for the edited block and zero for the rest. (Code blocks lay out
  /// per-line via [_codeLayoutFor], so they are not handled here.)
  TextPainter _layoutFor(TextBlockNode node, double width) {
    final style = _resolveStyle();
    final Object contentKey = node.delta;
    final cached = _layoutCache[node.id];
    if (cached != null &&
        cached.width == width &&
        identical(cached.contentKey, contentKey) &&
        cached.styleVersion == _styleVersion) {
      return cached.painter;
    }
    cached?.painter.dispose();
    final span =
        deltaToTextSpan(node.delta, baseStyleFor(node, style), style) as TextSpan;
    // Base direction from the first strong character, so RTL scripts
    // (Arabic/Hebrew) render and align correctly; TextPainter then handles
    // intra-line bidi reordering, caret geometry and selection rects.
    final painter = TextPainter(
      text: span,
      textDirection: resolveBaseDirection(node.delta.toPlainText()),
    )..layout(maxWidth: width);
    _layoutCache[node.id] =
        _CachedLayout(width, contentKey, painter, _styleVersion);
    return painter;
  }

  /// Returns a per-line [CodeLayout] for [node] at [width], reusing the cache so
  /// editing one line re-shapes only that line (O(changed line)). If the code,
  /// width and style are all unchanged the cached layout is returned verbatim
  /// (no tokenize, no shape — caret-blink/selection repaints stay free).
  CodeLayout _codeLayoutFor(CodeBlockNode node, double width) {
    final style = _resolveStyle();
    final prev = _codeLayoutCache[node.id];
    if (prev != null &&
        prev.width == width &&
        prev.styleVersion == _styleVersion &&
        prev.code == node.code) {
      return prev;
    }
    final base = style.codeTextStyle.copyWith(backgroundColor: null);
    final next = CodeLayout.build(
      code: node.code,
      language: node.language,
      baseStyle: base,
      highlighter: _highlighter,
      width: width,
      styleVersion: _styleVersion,
      previous: prev,
    );
    _codeLayoutCache[node.id] = next;
    return next;
  }

  void _disposeLayoutCache() {
    for (final c in _layoutCache.values) {
      c.painter.dispose();
    }
    _layoutCache.clear();
    for (final c in _codeLayoutCache.values) {
      c.dispose();
    }
    _codeLayoutCache.clear();
  }

  /// Bumped when the resolved style changes so cached layouts invalidate.
  int get _styleVersion {
    _resolveStyle(); // ensure the memo (and version) is current
    return _styleVer;
  }

  // ── Active block + IME sync ──────────────────────────────────────────────

  /// The IME window: a [DocumentText] over only the editable block(s) the
  /// selection touches — one block for a collapsed caret, the contiguous span
  /// for a cross-block selection. The OS never sees the whole document, so a
  /// keystroke costs O(active block), not O(document) (cf. CodeMirror/ProseMirror
  /// local-change model; super_editor's selected-node IME serialization).
  /// Returns null when the selection has no editable block (e.g. an image).
  DocumentText? _imeWindow() {
    final doc = _c.document;
    bool editable(Node n) => n is TextBlockNode || n is CodeBlockNode;
    final sel = _c.selection;
    int lo, hi;
    if (sel == null) {
      lo = hi = 0;
    } else {
      final iBase = doc.indexOfId(sel.base.nodeId);
      final iExt = doc.indexOfId(sel.extent.nodeId);
      if (iBase < 0 || iExt < 0) {
        lo = hi = 0;
      } else {
        lo = iBase < iExt ? iBase : iExt;
        hi = iBase < iExt ? iExt : iBase;
      }
    }
    // Include one editable neighbor on each side so backspace-at-start merges
    // with the previous block and Enter-splits flow into the next — without
    // pulling in the whole document (latency stays O(selection span + 2)).
    final from = (lo - 1).clamp(0, doc.length - 1);
    final to = (hi + 1).clamp(0, doc.length - 1);
    final window = <Node>[
      for (var i = from; i <= to; i++)
        if (editable(doc.nodeAt(i))) doc.nodeAt(i),
    ];
    if (window.isEmpty) {
      // Fall back to the first editable block so an empty doc still types.
      final first = doc.length > 0 ? doc.nodeAt(0) : null;
      if (first != null && editable(first)) window.add(first);
    }
    if (window.isEmpty) return null;
    return DocumentText.of(Document(window));
  }

  TextBlockNode? get _activeBlock {
    final sel = _c.selection;
    final id = sel?.extent.nodeId;
    final node = id != null ? _c.document.nodeById(id) : null;
    if (node is TextBlockNode) return node;
    final first = _c.document.nodeAt(0);
    return first is TextBlockNode ? first : null;
  }

  // ── Accessibility (screen-reader text-field semantics) ───────────────────
  //
  // The hand-painted surface is otherwise invisible to TalkBack/VoiceOver/NVDA.
  // We expose the active block as an editable text field (value + caret) and
  // wire the platform cursor-move / set-selection semantic actions to the same
  // CaretMotor the keyboard uses, reusing Flutter's `SemanticsConfiguration`
  // (via the `Semantics` widget) rather than reimplementing a11y.

  /// The active block's visible text, or '' — the screen-reader value.
  String _semanticsValue() => _activeBlock?.delta.toPlainText() ?? '';

  void _semanticsSetSelection(TextSelection sel) {
    final active = _activeBlock;
    if (active == null) return;
    _focusNode.requestFocus();
    _c.setSelection(DocumentSelection(
      base: DocumentPosition.text(active.id, sel.baseOffset),
      extent: DocumentPosition.text(active.id, sel.extentOffset),
    ));
  }

  void _semanticsMoveCursor({required bool forward, required bool extend}) {
    _verticalGoalX = null;
    if (_c.selection == null) {
      final active = _activeBlock;
      if (active == null) return;
      _c.placeCaretAt(DocumentPosition.text(active.id, 0));
    }
    _c.moveSelection(
        forward: forward,
        granularity: CaretGranularity.character,
        extend: extend);
  }

  /// When the caret is in a table cell, returns (tableId, row, col); else null.
  /// A cell is a contextual sub-editor: the IME windows to just that cell.
  (String, int, int)? get _activeCell {
    final ext = _c.selection?.extent;
    final np = ext?.nodePosition;
    if (np is TableCellPosition) return (ext!.nodeId, np.row, np.col);
    return null;
  }

  Delta? _cellDelta((String, int, int) cell) {
    final t = _c.document.nodeById(cell.$1);
    if (t is! TableNode) return null;
    return t.rows[cell.$2][cell.$3];
  }

  /// Applies an IME edit (cell-local offsets) to the active cell through the
  /// unified command pipeline.
  void _applyCellEdit(
      (String, int, int) cell, int start, int deleted, String inserted) {
    final (id, r, col) = cell;
    _c.setSelection(DocumentSelection(
      base: DocumentPosition(nodeId: id, nodePosition: TableCellPosition(r, col, start)),
      extent: DocumentPosition(
          nodeId: id, nodePosition: TableCellPosition(r, col, start + deleted)),
    ));
    if (inserted.isEmpty) {
      _c.deleteBackward();
    } else {
      _c.insertText(inserted);
    }
  }

  /// Mirrors the selection's block window to the IME (§13 — one editor; the
  /// window keeps it O(active block) per keystroke, not O(document)).
  void _syncImeFromModel() {
    // When editing a table cell, the IME windows to that cell's text.
    final cell = _activeCell;
    if (cell != null) {
      final delta = _cellDelta(cell);
      if (delta != null) {
        final text = delta.toPlainText();
        final sel = _c.selection!;
        final bp = sel.base.nodePosition;
        final ep = sel.extent.nodePosition;
        final base = (bp is TableCellPosition && bp.row == cell.$2 && bp.col == cell.$3)
            ? bp.offset
            : text.length;
        final extent = ep is TableCellPosition ? ep.offset : text.length;
        _imeValue = TextEditingValue(
          text: text,
          selection: TextSelection(
            baseOffset: base.clamp(0, text.length),
            extentOffset: extent.clamp(0, text.length),
          ),
        );
        if (_connection?.attached ?? false) _connection!.setEditingState(_imeValue);
        return;
      }
    }
    final dt = _imeWindow();
    if (dt == null) {
      _imeValue = const TextEditingValue();
      if (_connection?.attached ?? false) _connection!.setEditingState(_imeValue);
      return;
    }
    final text = dt.text;
    final sel = _c.selection;
    var base = text.length;
    var extent = text.length;
    if (sel != null && dt.covers(sel.base.nodeId) && dt.covers(sel.extent.nodeId)) {
      base = dt.offsetOf(sel.base);
      extent = dt.offsetOf(sel.extent);
    }
    final composing = (_composing.isValid && _composing.end <= text.length)
        ? _composing
        : TextRange.empty;
    _imeValue = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: base.clamp(0, text.length),
        extentOffset: extent.clamp(0, text.length),
      ),
      composing: composing,
    );
    if (_connection?.attached ?? false) _connection!.setEditingState(_imeValue);
  }

  void _openConnection() {
    if (widget.readOnly) return;
    if (_connection != null && _connection!.attached) {
      _syncImeFromModel();
      return;
    }
    _connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        // Precise edits (incl. IME composition / autocorrect) via deltas.
        enableDeltaModel: true,
      ),
    );
    _syncImeFromModel();
    _connection!
      ..show()
      ..setEditingState(_imeValue);
  }

  void _closeConnection() {
    _connection?.close();
    _connection = null;
  }

  // ── TextInputClient ──────────────────────────────────────────────────────

  @override
  TextEditingValue get currentTextEditingValue => _imeValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    // Table cell window: edits map to the active cell.
    final cell = _activeCell;
    if (cell != null) {
      final old = _imeValue.text;
      if (value.text == old) {
        final s = value.selection;
        if (s.isValid) {
          _c.setSelection(DocumentSelection(
            base: DocumentPosition(
                nodeId: cell.$1,
                nodePosition: TableCellPosition(cell.$2, cell.$3, s.baseOffset)),
            extent: DocumentPosition(
                nodeId: cell.$1,
                nodePosition: TableCellPosition(cell.$2, cell.$3, s.extentOffset)),
          ));
        }
        _imeValue = value;
        return;
      }
      final (start, deleted, inserted) = _diff(old, value.text);
      _applyCellEdit(cell, start, deleted, inserted);
      return;
    }
    final dt = _imeWindow();
    if (dt == null) {
      _imeValue = value;
      return;
    }
    final old = _imeValue.text;
    if (value.text == old) {
      // Selection-only change — map window offsets back to a document selection.
      final s = value.selection;
      if (s.isValid) _c.setSelection(dt.selectionOf(s.baseOffset, s.extentOffset));
      _imeValue = value;
      return;
    }
    final (start, deleted, inserted) = _diff(old, value.text);
    _applyStreamEdit(dt, start, deleted, inserted);
    // Model change triggers _onControllerChanged → _syncImeFromModel.
  }

  /// Precise IME path (delta model): the platform reports exactly what changed,
  /// in *document-stream* offsets, so each delta maps unambiguously to a
  /// (possibly cross-block) edit — no special-casing, IME composition survives.
  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    for (final delta in deltas) {
      _composing = delta.composing;
      // Table cell window: cell-local offsets map to the active cell.
      final cell = _activeCell;
      if (cell != null) {
        final edit = editFromDelta(delta);
        if (edit != null) _applyCellEdit(cell, edit.$1, edit.$2, edit.$3);
        continue;
      }
      final dt = _imeWindow(); // window only the selection's block(s)
      if (dt == null) continue;
      final edit = editFromDelta(delta);
      if (edit == null) {
        final s = delta.selection;
        if (s.isValid) _c.setSelection(dt.selectionOf(s.baseOffset, s.extentOffset));
        continue;
      }
      _applyStreamEdit(dt, edit.$1, edit.$2, edit.$3);
    }
  }

  /// Applies a window-offset stream edit through the unified command pipeline.
  /// [dt] is the IME window; an edit that spans a block separator within the
  /// window naturally merges/splits blocks — no per-block special-casing.
  void _applyStreamEdit(DocumentText dt, int start, int deleted, String inserted) {
    if (!dt.coversAny) return;
    _c.setSelection(dt.selectionOf(start, start + deleted));
    if (inserted.isEmpty) {
      _c.deleteBackward();
    } else if (inserted == '\n') {
      if (deleted > 0) _c.deleteBackward();
      _c.splitBlock();
    } else if (inserted.contains('\n')) {
      final segments = inserted.split('\n');
      _c.insertText(segments.first);
      for (final seg in segments.skip(1)) {
        _c.splitBlock();
        if (seg.isNotEmpty) _c.insertText(seg);
      }
    } else {
      _c.insertText(inserted);
    }
  }

  /// Computes the minimal `(start, deletedLength, insertedText)` between two
  /// strings using common prefix/suffix.
  static (int, int, String) _diff(String a, String b) {
    var start = 0;
    final minLen = math.min(a.length, b.length);
    while (start < minLen && a.codeUnitAt(start) == b.codeUnitAt(start)) {
      start++;
    }
    var endA = a.length;
    var endB = b.length;
    while (endA > start &&
        endB > start &&
        a.codeUnitAt(endA - 1) == b.codeUnitAt(endB - 1)) {
      endA--;
      endB--;
    }
    return (start, endA - start, b.substring(start, endB));
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline) {
      _c.splitBlock();
    }
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    _connection = null;
  }

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void didChangeInputControl(
      TextInputControl? oldControl, TextInputControl? newControl) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  bool onFocusReceived() => false;

  @override
  void performSelector(String selectorName) {}

  @override
  void showToolbar() {}

  // ── Gestures ─────────────────────────────────────────────────────────────

  void _placeCaret(Node node, Offset localPos, double width) {
    if (widget.readOnly) return;
    final int offset = node is CodeBlockNode
        ? _codeLayoutFor(node, width).getPositionForOffset(localPos)
        : _layoutFor(node as TextBlockNode, width)
            .getPositionForOffset(localPos)
            .offset;
    _focusNode.requestFocus();
    final target = DocumentPosition.text(node.id, offset);
    // Shift+click extends the existing selection (possibly across blocks).
    if (HardwareKeyboard.instance.isShiftPressed && _c.selection != null) {
      _c.extendSelectionTo(target);
    } else {
      _c.placeCaretAt(target);
    }
  }

  /// Extends the selection during a drag, hit-testing every block so the extent
  /// can move into a different block (cross-block selection). Falls back to the
  /// gesture's owning [node] when the pointer is between blocks.
  void _extendSelectionGlobal(
      Node node, DragUpdateDetails d, double width) {
    if (widget.readOnly) return;
    final hit = _blockAtGlobal(d.globalPosition);
    final (target, offset) = hit ?? _localHit(node, d.localPosition, width);
    _c.extendSelectionTo(DocumentPosition.text(target, offset));
  }

  (String, int) _localHit(Node node, Offset localPos, double width) {
    final offset = node is CodeBlockNode
        ? _codeLayoutFor(node, width).getPositionForOffset(localPos)
        : _layoutFor(node as TextBlockNode, width)
            .getPositionForOffset(localPos)
            .offset;
    return (node.id, offset);
  }

  /// Returns the (nodeId, text offset) for the editable block (text or code)
  /// whose painted area contains [globalPos], or null if none does.
  (String, int)? _blockAtGlobal(Offset globalPos) {
    // Iterate only blocks that have been built (a paint key with a live render
    // object) — i.e. roughly the viewport — never the whole document.
    for (final entry in _paintKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final local = box.globalToLocal(globalPos);
      if (local.dy < 0 || local.dy > box.size.height) continue;
      final n = _c.document.nodeById(entry.key);
      if (n is CodeBlockNode) {
        return (entry.key, _codeLayoutFor(n, box.size.width)
            .getPositionForOffset(local));
      }
      if (n is! TextBlockNode) continue;
      final tp = _layoutFor(n, box.size.width);
      return (entry.key, tp.getPositionForOffset(local).offset);
    }
    return null;
  }

  // ── Vertical caret movement (needs paint geometry + goal column) ─────────

  /// Moves the caret one visual line up/down, preserving the goal column. This
  /// is the one movement that needs layout: it reads the caret's pixel x, then
  /// asks the line above/below (or the adjacent block) for the position nearest
  /// that x — super_editor's "get X → position near X", with Flutter's goal-
  /// column persistence.
  void _moveCaretVertical({required bool forward, required bool extend}) {
    if (widget.readOnly) return;
    final sel = _c.selection;
    if (sel == null) return;
    final caret = _caretLocalGeometry(sel.extent);
    if (caret == null) return;
    final goalX = _verticalGoalX ??= caret.$1.dx;
    final to = _positionOneLineFrom(sel.extent, caret, goalX, forward: forward);
    if (to == null) return;
    _verticalMoving = true;
    if (extend) {
      _c.setSelection(DocumentSelection(base: sel.base, extent: to));
    } else {
      _c.placeCaretAt(to);
    }
    _verticalMoving = false;
  }

  /// The caret's block-local offset and full height for [pos], or null when the
  /// block isn't laid out / isn't a vertically-navigable text block.
  (Offset, double)? _caretLocalGeometry(DocumentPosition pos) {
    final node = _c.document.nodeById(pos.nodeId);
    final np = pos.nodePosition;
    if (np is! TextNodePosition) return null;
    if (node is CodeBlockNode) {
      final cl = _codeLayoutCache[node.id];
      if (cl == null) return null;
      return (cl.getOffsetForCaret(np.offset), cl.getFullHeightForCaret(np.offset));
    }
    if (node is TextBlockNode) {
      final tp = _layoutCache[node.id]?.painter;
      if (tp == null) return null;
      final tpos = TextPosition(offset: np.offset);
      return (
        tp.getOffsetForCaret(tpos, Rect.zero),
        tp.getFullHeightForCaret(tpos, Rect.zero),
      );
    }
    return null;
  }

  DocumentPosition? _positionOneLineFrom(
      DocumentPosition pos, (Offset, double) caret, double goalX,
      {required bool forward}) {
    final node = _c.document.nodeById(pos.nodeId);
    final (off, height) = caret;
    final probeY = forward ? off.dy + height + 1 : off.dy - 1;

    // Try staying within the same block (another visual line of a wrapped
    // paragraph, or another physical line of a code block).
    if (node is TextBlockNode) {
      final tp = _layoutCache[node.id]?.painter;
      if (tp != null && probeY >= 0 && probeY <= tp.height) {
        final p = tp.getPositionForOffset(Offset(goalX, probeY));
        return DocumentPosition.text(node.id, p.offset);
      }
    } else if (node is CodeBlockNode) {
      final cl = _codeLayoutCache[node.id];
      if (cl != null && probeY >= 0 && probeY <= cl.height) {
        return DocumentPosition.text(
            node.id, cl.getPositionForOffset(Offset(goalX, probeY)));
      }
    }

    // Crossed the block edge → nearest position at goalX in the adjacent block.
    final neighbour = forward
        ? _adjacentEditable(pos.nodeId, 1)
        : _adjacentEditable(pos.nodeId, -1);
    if (neighbour == null) return null;
    return _positionNearXInBlock(neighbour, goalX, atTop: forward);
  }

  /// The position nearest [goalX] on the first ([atTop]) or last visual line of
  /// [node], laying it out on demand if it isn't cached (off-screen neighbour).
  DocumentPosition _positionNearXInBlock(Node node, double goalX,
      {required bool atTop}) {
    final width = _lastBlockWidth > 0 ? _lastBlockWidth : 600.0;
    if (node is CodeBlockNode) {
      final cl = _codeLayoutFor(node, width);
      final y = atTop ? 0.0 : math.max(0.0, cl.height - 1);
      return DocumentPosition.text(
          node.id, cl.getPositionForOffset(Offset(goalX, y)));
    }
    final tp = _layoutFor(node as TextBlockNode, width);
    final y = atTop ? 0.0 : math.max(0.0, tp.height - 1);
    final p = tp.getPositionForOffset(Offset(goalX, y));
    return DocumentPosition.text(node.id, p.offset);
  }

  /// The next editable (text/code) block [dir] (±1) steps from [id].
  Node? _adjacentEditable(String id, int dir) {
    final doc = _c.document;
    var i = doc.indexOfId(id);
    if (i < 0) return null;
    for (i += dir; i >= 0 && i < doc.length; i += dir) {
      final n = doc.nodeAt(i);
      if (n is TextBlockNode || n is CodeBlockNode) return n;
    }
    return null;
  }

  // ── Touch selection handles + magnifier ──────────────────────────────────
  //
  // EditableText draws draggable handles, a magnifier, and the toolbar for
  // free; a hand-painted editor must provide them. We reuse Material's handle
  // visuals (`MaterialTextSelectionControls`) and `RawMagnifier`, positioned in
  // the app Overlay at the selection endpoints (read from the per-block paint
  // keys, in global coordinates — the same trick `SelectionOverlay` uses).

  OverlayEntry? _handlesEntry;
  final MaterialTextSelectionControls _handleControls =
      MaterialTextSelectionControls();

  /// Global position of the active handle drag (drives the magnifier), or null.
  Offset? _handleDragGlobal;

  bool get _isTouchPlatform {
    final p = Theme.of(context).platform;
    return p == TargetPlatform.android || p == TargetPlatform.iOS;
  }

  /// Inserts/updates/removes the selection-handle overlay to match the current
  /// selection. Called post-frame (after layout) so the paint keys resolve.
  void _syncSelectionHandles() {
    if (!mounted) return;
    final sel = _c.selection;
    final show = !widget.readOnly &&
        _focusNode.hasFocus &&
        _isTouchPlatform &&
        sel != null &&
        !sel.isCollapsed &&
        _c.mode == EditorMode.wysiwyg;
    if (!show) {
      _handlesEntry?.remove();
      _handlesEntry = null;
      return;
    }
    if (_handlesEntry == null) {
      _handlesEntry = OverlayEntry(builder: _buildHandlesOverlay);
      Overlay.of(context).insert(_handlesEntry!);
    } else {
      _handlesEntry!.markNeedsBuild();
    }
  }

  /// The global caret point (bottom of the line) + line height for [pos].
  (Offset, double)? _globalCaret(DocumentPosition pos) {
    final box = _paintKeys[pos.nodeId]?.currentContext?.findRenderObject()
        as RenderBox?;
    if (box == null || !box.attached) return null;
    final geo = _caretLocalGeometry(pos);
    if (geo == null) return null;
    final (local, height) = geo;
    return (box.localToGlobal(local + Offset(0, height)), height);
  }

  int _comparePositions(DocumentPosition a, DocumentPosition b) {
    final ia = _c.document.indexOfId(a.nodeId);
    final ib = _c.document.indexOfId(b.nodeId);
    if (ia != ib) return ia.compareTo(ib);
    int o(NodePosition p) => p is TextNodePosition
        ? p.offset
        : p is TableCellPosition
            ? p.offset
            : 0;
    return o(a.nodePosition).compareTo(o(b.nodePosition));
  }

  Widget _buildHandlesOverlay(BuildContext context) {
    final sel = _c.selection;
    if (sel == null || sel.isCollapsed) return const SizedBox.shrink();
    final startIsBase = _comparePositions(sel.base, sel.extent) <= 0;
    final startPos = startIsBase ? sel.base : sel.extent;
    final endPos = startIsBase ? sel.extent : sel.base;
    final start = _globalCaret(startPos);
    final end = _globalCaret(endPos);
    if (start == null || end == null) return const SizedBox.shrink();

    final children = <Widget>[
      _handleWidget(const Key('markey_handle_start'),
          TextSelectionHandleType.left, start.$1, start.$2, isStart: true),
      _handleWidget(const Key('markey_handle_end'),
          TextSelectionHandleType.right, end.$1, end.$2, isStart: false),
    ];
    if (_handleDragGlobal != null) {
      children.add(_magnifierWidget(_handleDragGlobal!));
    }
    return Stack(children: children);
  }

  Widget _handleWidget(Key key, TextSelectionHandleType type, Offset globalPos,
      double lineHeight,
      {required bool isStart}) {
    final anchor = _handleControls.getHandleAnchor(type, lineHeight);
    final size = _handleControls.getHandleSize(lineHeight);
    return Positioned(
      left: globalPos.dx - anchor.dx,
      top: globalPos.dy - anchor.dy,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.translucent,
        onPanStart: (d) {
          setState(() => _handleDragGlobal = d.globalPosition);
          _handlesEntry?.markNeedsBuild();
        },
        onPanUpdate: (d) {
          _dragHandle(d.globalPosition, lineHeight, isStart: isStart);
          setState(() => _handleDragGlobal = d.globalPosition);
          _handlesEntry?.markNeedsBuild();
        },
        onPanEnd: (_) {
          setState(() => _handleDragGlobal = null);
          _handlesEntry?.markNeedsBuild();
        },
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: _handleControls.buildHandle(
              context, type, lineHeight, () {}),
        ),
      ),
    );
  }

  /// A loupe centered above the drag point that magnifies the editor beneath it.
  Widget _magnifierWidget(Offset global) {
    const magnifierSize = Size(80, 48);
    return Positioned(
      left: global.dx - magnifierSize.width / 2,
      top: global.dy - magnifierSize.height - 24,
      child: IgnorePointer(
        child: RawMagnifier(
          key: const Key('markey_magnifier'),
          size: magnifierSize,
          magnificationScale: 1.5,
          decoration: const MagnifierDecoration(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(8))),
          ),
          focalPointOffset: Offset(0, magnifierSize.height / 2 + 24),
        ),
      ),
    );
  }

  void _dragHandle(Offset global, double lineHeight, {required bool isStart}) {
    // The handle hangs below the caret line, so probe a line up to hit the text.
    final hit = _blockAtGlobal(global - Offset(0, lineHeight));
    final sel = _c.selection;
    if (hit == null || sel == null) return;
    final pos = DocumentPosition.text(hit.$1, hit.$2);
    final startIsBase = _comparePositions(sel.base, sel.extent) <= 0;
    // Move the dragged end; keep the other fixed.
    final movingBase = isStart == startIsBase;
    _c.setSelection(movingBase
        ? DocumentSelection(base: pos, extent: sel.extent)
        : DocumentSelection(base: sel.base, extent: pos));
  }

  // ── Find & replace ─────────────────────────────────────────────────────

  void _openFind() {
    if (!_showFind) setState(() => _showFind = true);
    _runFind();
  }

  void _closeFind() => setState(() => _showFind = false);

  void _runFind() {
    final matches = _c.findMatches(_findController.text);
    setState(() {
      _matches = matches;
      _matchIndex = matches.isEmpty ? -1 : 0;
    });
    if (_matchIndex >= 0) _c.selectMatch(_matches[_matchIndex]);
  }

  void _findStep(int dir) {
    if (_matches.isEmpty) return;
    setState(() {
      _matchIndex = (_matchIndex + dir + _matches.length) % _matches.length;
    });
    _c.selectMatch(_matches[_matchIndex]);
  }

  void _replaceAllFind() {
    _c.replaceAll(_findController.text, _replaceController.text);
    _runFind();
  }

  /// Reads the clipboard and smart-pastes it (parsing Markdown structure).
  Future<void> _handlePaste() async {
    if (widget.readOnly) return;
    await _c.paste(bridge: widget.clipboard);
  }

  Future<void> _handleCopy() => _c.copy(bridge: widget.clipboard);

  /// Shows the native context menu (copy/cut/paste/select-all) at [globalPos],
  /// with the items that apply to the current selection and edit mode.
  void _showContextMenu(Offset globalPos) {
    _focusNode.requestFocus();
    final hasSelection =
        _c.selection != null && !_c.selection!.isCollapsed;
    final items = <ContextMenuButtonItem>[
      if (hasSelection)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            _hideContextMenu();
            _handleCopy();
          },
        ),
      if (hasSelection && !widget.readOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          onPressed: () {
            _hideContextMenu();
            _handleCut();
          },
        ),
      if (!widget.readOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: () {
            _hideContextMenu();
            _handlePaste();
          },
        ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed: () {
          _hideContextMenu();
          _c.selectAll();
        },
      ),
    ];
    _contextMenu.show(
      context: context,
      contextMenuBuilder: (_) => AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(primaryAnchor: globalPos),
        buttonItems: items,
      ),
    );
  }

  void _hideContextMenu() {
    if (_contextMenu.isShown) _contextMenu.remove();
  }

  // ── Mouse drag-selection (coexists with scroll) ──────────────────────────
  // A precise pointer (mouse/stylus) drag selects text — possibly across
  // blocks — while the scroll view is frozen for the drag. Touch keeps
  // scrolling (use shift+click / select-all to make a cross-block selection).

  bool _isPreciseDrag(PointerEvent e) =>
      (e.kind == PointerDeviceKind.mouse ||
          e.kind == PointerDeviceKind.stylus) &&
      (e.buttons & kPrimaryButton) != 0;

  void _onMousePointerDown(PointerDownEvent e) {
    if (widget.readOnly || !_isPreciseDrag(e)) return;
    final hit = _blockAtGlobal(e.position);
    if (hit == null) return;
    _focusNode.requestFocus();
    setState(() => _mouseSelecting = true);
    _c.placeCaretAt(DocumentPosition.text(hit.$1, hit.$2));
  }

  void _onMousePointerMove(PointerMoveEvent e) {
    if (!_mouseSelecting) return;
    final hit = _blockAtGlobal(e.position);
    if (hit == null) return;
    // The anchor is the caret set on pointer-down; extend keeps it.
    _c.extendSelectionTo(DocumentPosition.text(hit.$1, hit.$2));
  }

  void _onMousePointerUp(PointerEvent e) {
    if (!_mouseSelecting) return;
    setState(() => _mouseSelecting = false);
  }

  Future<void> _handleCut() async {
    if (widget.readOnly) return;
    await _c.cut(bridge: widget.clipboard);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final style = _resolveStyle();
    final body = _c.mode == EditorMode.source ? _buildSource() : _buildWysiwyg();
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToolbar) _Toolbar(controller: _c),
        if (_showFind && _c.mode == EditorMode.wysiwyg) _buildFindBar(style),
        Expanded(child: body),
      ],
    );
    // Accept OS drag-and-drop of text/images (native super_drag_and_drop; no JS).
    if (widget.enableDrop && !widget.readOnly) {
      content = sdd.DropRegion(
        formats: const [
          sc.Formats.plainText,
          sc.Formats.htmlText,
          sc.Formats.fileUri,
          sc.Formats.uri,
        ],
        hitTestBehavior: HitTestBehavior.opaque,
        onDropOver: (_) => sdd.DropOperation.copy,
        onPerformDrop: _onPerformDrop,
        child: content,
      );
    }
    return content;
  }

  Future<void> _onPerformDrop(sdd.PerformDropEvent event) async {
    final items = <DroppedItem>[];
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;
      if (reader.canProvide(sc.Formats.plainText)) {
        final text = await _readValue(reader, sc.Formats.plainText);
        if (text != null && text.isNotEmpty) items.add(DroppedItem.text(text));
      } else if (reader.canProvide(sc.Formats.fileUri)) {
        final uri = await _readValue(reader, sc.Formats.fileUri);
        if (uri != null) {
          final s = uri.toString();
          items.add(_looksLikeImage(s)
              ? DroppedItem.image(s)
              : DroppedItem.text(s));
        }
      }
    }
    if (items.isNotEmpty) _c.applyDrop(items);
  }

  /// Adapts super_clipboard's callback-based [sc.DataReader.getValue] to a
  /// Future.
  Future<T?> _readValue<T extends Object>(
      sc.DataReader reader, sc.ValueFormat<T> format) {
    final completer = Completer<T?>();
    reader.getValue<T>(
      format,
      (value) => completer.complete(value),
      onError: (_) => completer.complete(null),
    );
    return completer.future;
  }

  static bool _looksLikeImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg');
  }

  Widget _buildFindBar(EditorStyle style) {
    return Material(
      key: const Key('markey_find_bar'),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  key: const Key('markey_find_field'),
                  controller: _findController,
                  decoration: const InputDecoration(
                      hintText: 'Find', isDense: true),
                  onChanged: (_) => _runFind(),
                ),
              ),
              const SizedBox(width: 8),
              Text(_matches.isEmpty ? '0/0' : '${_matchIndex + 1}/${_matches.length}'),
              IconButton(
                key: const Key('markey_find_prev'),
                tooltip: 'Previous',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => _findStep(-1),
              ),
              IconButton(
                key: const Key('markey_find_next'),
                tooltip: 'Next',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => _findStep(1),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  key: const Key('markey_find_replace_field'),
                  controller: _replaceController,
                  decoration: const InputDecoration(
                      hintText: 'Replace', isDense: true),
                ),
              ),
              TextButton(
                key: const Key('markey_find_replaceall'),
                onPressed: _replaceAllFind,
                child: const Text('All'),
              ),
              IconButton(
                key: const Key('markey_find_close'),
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: _closeFind,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSource() {
    // On entering source mode, place the caret where it was in WYSIWYG.
    final TextSelection selection;
    if (_enterSourcePending) {
      _enterSourcePending = false;
      final len = _c.markdown.length;
      selection = TextSelection(
        baseOffset: _c.sourceCaretBase.clamp(0, len),
        extentOffset: _c.sourceCaret.clamp(0, len),
      );
    } else if (_sourceController.selection.isValid &&
        _sourceController.selection.end <= _c.markdown.length) {
      selection = _sourceController.selection;
    } else {
      selection = TextSelection.collapsed(offset: _c.markdown.length);
    }
    _sourceController.value =
        TextEditingValue(text: _c.markdown, selection: selection);
    final style = _resolveStyle();
    return Padding(
      padding: style.padding,
      child: TextField(
        key: const Key('markey_source_field'),
        controller: _sourceController,
        readOnly: widget.readOnly,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
        ),
        style: style.codeTextStyle.copyWith(backgroundColor: null),
        onChanged: _c.updateSourceText,
      ),
    );
  }

  /// Builds the rendered widget for a single block (without the reorder handle).
  Widget _blockContent(Node node, EditorStyle style) {
    // Open block set: a registered custom renderer takes precedence (§13.5).
    if (node is CustomBlockNode) {
      final builder = widget.blockRegistry?.builderFor(node.blockType);
      return builder?.call(context, node, style) ?? const SizedBox.shrink();
    }
    if (node is HtmlBlockNode) return _buildHtmlBlock(node, style);
    if (node is CodeBlockNode) return _buildCodeBlock(node, style);
    if (node is HorizontalRuleNode) return _buildHr(node, style);
    if (node is ImageNode) {
      return Semantics(
        image: true,
        excludeSemantics: true,
        label: (node.alt == null || node.alt!.isEmpty) ? 'image' : node.alt,
        child: _buildImage(node, style),
      );
    }
    if (node is MathBlockNode) return _buildMath(node, style);
    if (node is TableNode) {
      return widget.readOnly
          ? _buildTable(node, style)
          : _buildEditableTable(node, style);
    }
    if (node is MermaidNode) {
      return widget.diagramRenderer.build(context, node, style);
    }
    if (node is FrontMatterNode) return _buildFrontMatter(node, style);
    if (node is TextBlockNode) {
      return Semantics(
        header: node.type == BlockType.heading,
        label: node.delta.toPlainText(),
        child: _buildBlock(node, style),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildWysiwyg() {
    final style = _resolveStyle();
    final slashQuery = _slashSuppressed ? null : _activeSlashQuery();
    return Shortcuts(
      shortcuts: _shortcuts(),
      child: Actions(
        actions: _actions(),
        child: Focus(
          focusNode: _focusNode,
          child: Semantics(
            container: true,
            textField: true,
            multiline: true,
            readOnly: widget.readOnly,
            // The active block's visible text + caret, so screen readers treat
            // the editor as an editable field with a movable caret. Built only
            // when semantics are enabled (a screen reader is active).
            value: _semanticsValue(),
            onSetSelection: widget.readOnly ? null : _semanticsSetSelection,
            onMoveCursorForwardByCharacter: widget.readOnly
                ? null
                : (extend) => _semanticsMoveCursor(forward: true, extend: extend),
            onMoveCursorBackwardByCharacter: widget.readOnly
                ? null
                : (extend) => _semanticsMoveCursor(forward: false, extend: extend),
            child: Stack(
            children: [
              Listener(
                onPointerDown: _onMousePointerDown,
                onPointerMove: _onMousePointerMove,
                onPointerUp: _onMousePointerUp,
                onPointerCancel: _onMousePointerUp,
                child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _focusNode.requestFocus,
                onSecondaryTapDown: (d) => _showContextMenu(d.globalPosition),
                onLongPressStart: (d) => _showContextMenu(d.globalPosition),
                child: ListView.separated(
                  physics: _mouseSelecting
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: style.padding,
                  itemCount: _c.document.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(height: style.blockSpacing),
                  itemBuilder: (context, index) {
                    final node = _c.document.nodeAt(index);
                    final content = _blockContent(node, style);
                    if (widget.readOnly) return content;
                    return _ReorderableBlock(
                      index: index,
                      handleKey: ValueKey('markey-drag-${node.id}'),
                      onReorder: _c.reorderBlock,
                      accent: style.caretColor,
                      child: content,
                    );
                  },
                ),
              ),
              ),
              if (widget.placeholder != null && _c.document.isEmpty)
                Positioned(
                  left: style.padding.left + (widget.readOnly ? 0 : 24),
                  top: style.padding.top,
                  child: IgnorePointer(
                    child: Text(
                      widget.placeholder!,
                      key: const Key('markey_placeholder'),
                      style: style.baseTextStyle.copyWith(
                        color: style.baseTextStyle.color?.withValues(alpha: 0.4) ??
                            style.caretColor.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              if (slashQuery != null)
                Positioned(
                  left: style.padding.left,
                  top: style.padding.top,
                  child: SlashMenu(
                    key: const Key('markey_slash_menu'),
                    items: _slashItems,
                    query: slashQuery,
                    onSelected: _selectSlash,
                  ),
                ),
              if (slashQuery == null && _hasRangeSelection())
                Positioned(
                  left: 0,
                  right: 0,
                  top: style.padding.top,
                  child: Center(child: _SelectionToolbar(controller: _c)),
                ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  bool _hasInlineMath(TextBlockNode node) =>
      node.delta.runs.any((r) => r.attributes[InlineAttr.math] == true);

  bool _isActiveBlock(TextBlockNode node) =>
      _focusNode.hasFocus && _c.selection?.extent.nodeId == node.id;

  /// Read-mode rendering of a block that contains inline math: renders the math
  /// natively (KaTeX via `flutter_math_fork`) inline with the text. Tapping it
  /// focuses the block, which switches to the editable source view.
  Widget _renderedContent(TextBlockNode node, EditorStyle style) {
    final base = baseStyleFor(node, style);
    final spans = <InlineSpan>[
      for (final run in node.delta.runs)
        if (run.attributes[InlineAttr.math] == true)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Math.tex(
              run.text,
              textStyle: base,
              mathStyle: MathStyle.text,
              onErrorFallback: (e) => Text('\$${run.text}\$', style: base),
            ),
          )
        else
          TextSpan(
            text: run.text,
            style: styleForAttributes(run.attributes, base, style),
          ),
    ];
    return GestureDetector(
      key: ValueKey('markey-block-${node.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.readOnly
          ? null
          : () {
              _focusNode.requestFocus();
              _c.setSelection(DocumentSelection.collapsed(
                  DocumentPosition.text(node.id, node.delta.length)));
            },
      child: Text.rich(TextSpan(style: base, children: spans)),
    );
  }

  /// Wraps the editable text content with any block decoration (list marker,
  /// task checkbox, quote bar).
  Widget _buildBlock(TextBlockNode node, EditorStyle style) {
    final content = (_hasInlineMath(node) && !_isActiveBlock(node))
        ? _renderedContent(node, style)
        : _textContent(node, style);
    Widget indented(Widget w) => node.indent > 0
        ? Padding(padding: EdgeInsets.only(left: node.indent * 20.0), child: w)
        : w;
    switch (node.type) {
      case BlockType.bulletedListItem:
        return indented(_gutterRow(_marker('•', style), content));
      case BlockType.numberedListItem:
        return indented(_gutterRow(_marker('${node.number ?? 1}.', style), content));
      case BlockType.todoListItem:
        return indented(_gutterRow(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: node.checked ?? false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged:
                    widget.readOnly ? null : (_) => _c.toggleTodo(node.id),
              ),
            ),
          ),
          content,
        ));
      case BlockType.footnoteDef:
        return _gutterRow(
          _marker('[${node.footnoteLabel ?? ''}]', style),
          content,
        );
      case BlockType.definitionDesc:
        return Padding(
            padding: const EdgeInsets.only(left: 20), child: content);
      case BlockType.quote:
        if (node.callout != null) return _buildCallout(node, content);
        return Padding(
          padding: EdgeInsets.only(left: node.indent * 12.0),
          child: Container(
            key: ValueKey('markey-quote-${node.id}'),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                    color: style.caretColor.withValues(alpha: 0.4), width: 4),
              ),
            ),
            child: content,
          ),
        );
      default:
        return content;
    }
  }

  /// GitHub-style alert/callout palette and icon per kind.
  static const Map<String, (Color, IconData)> _calloutStyles = {
    'note': (Color(0xFF0969DA), Icons.info_outline),
    'tip': (Color(0xFF1A7F37), Icons.lightbulb_outline),
    'important': (Color(0xFF8250DF), Icons.campaign_outlined),
    'warning': (Color(0xFF9A6700), Icons.warning_amber),
    'caution': (Color(0xFFCF222E), Icons.report_outlined),
  };

  Widget _buildCallout(TextBlockNode node, Widget content) {
    final kind = node.callout!;
    final (color, icon) =
        _calloutStyles[kind] ?? (const Color(0xFF0969DA), Icons.info_outline);
    // Show the title row only on the first block of a callout run.
    final idx = _c.document.indexOfId(node.id);
    final prev = idx > 0 ? _c.document.nodeAt(idx - 1) : null;
    final isRunStart = !(prev is TextBlockNode &&
        prev.type == BlockType.quote &&
        prev.callout == kind);
    final title = '${kind[0].toUpperCase()}${kind.substring(1)}';
    return Container(
      key: ValueKey('markey-callout-${node.id}'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isRunStart)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(title,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          content,
        ],
      ),
    );
  }

  Widget _gutterRow(Widget marker, Widget content) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(right: 8), child: marker),
          Expanded(child: content),
        ],
      );

  Widget _marker(String text, EditorStyle style) =>
      Text(text, style: style.baseTextStyle);

  /// Raw HTML can't be rendered natively (no WebView/JS), so it's shown as
  /// source in a labelled card — preserved verbatim, never executed.
  Widget _buildHtmlBlock(HtmlBlockNode node, EditorStyle style) {
    final mono = style.codeTextStyle.copyWith(backgroundColor: null);
    final accent = style.caretColor;
    return Container(
      key: ValueKey('markey-html-${node.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.codeTextStyle.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.code, size: 16, color: accent.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text('html',
                style: mono.copyWith(
                    fontSize: (mono.fontSize ?? 14) * 0.8,
                    color: accent.withValues(alpha: 0.7))),
          ]),
          const SizedBox(height: 6),
          Text(node.html, style: mono),
        ],
      ),
    );
  }

  Widget _buildHr(HorizontalRuleNode node, EditorStyle style) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(
          key: ValueKey('markey-block-${node.id}'),
          thickness: 1,
          height: 1,
        ),
      );

  Widget _buildTable(TableNode node, EditorStyle style) {
    TextAlign textAlign(TableAlign a) => switch (a) {
          TableAlign.center => TextAlign.center,
          TableAlign.right => TextAlign.right,
          _ => TextAlign.left,
        };
    final borderColor = style.caretColor.withValues(alpha: 0.25);
    return Container(
      key: ValueKey('markey-block-${node.id}'),
      alignment: Alignment.centerLeft,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: borderColor),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (var r = 0; r < node.rowCount; r++)
            TableRow(
              decoration: r == 0
                  ? BoxDecoration(color: borderColor.withValues(alpha: 0.12))
                  : null,
              children: [
                for (var c = 0; c < node.columnCount; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: RichText(
                      textAlign: textAlign(node.alignments[c]),
                      text: deltaToTextSpan(
                        c < node.rows[r].length
                            ? node.rows[r][c]
                            : Delta.empty(),
                        r == 0
                            ? style.baseTextStyle
                                .copyWith(fontWeight: FontWeight.bold)
                            : style.baseTextStyle,
                        style,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// An editable table whose cells are sub-editors of the one editor: each cell
  /// renders with the shared caret/selection (no per-cell TextField) and edits
  /// through the unified command pipeline via [TableCellPosition].
  Widget _buildEditableTable(TableNode node, EditorStyle style) {
    final borderColor = style.caretColor.withValues(alpha: 0.25);
    return Container(
      key: ValueKey('markey-block-${node.id}'),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            defaultColumnWidth: const FixedColumnWidth(150),
            border: TableBorder.all(color: borderColor),
            children: [
              for (var r = 0; r < node.rowCount; r++)
                TableRow(
                  decoration: r == 0
                      ? BoxDecoration(color: borderColor.withValues(alpha: 0.12))
                      : null,
                  children: [
                    for (var c = 0; c < node.columnCount; c++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: _cellContent(node, r, c, style),
                      ),
                  ],
                ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('markey-table-addrow-${node.id}'),
                tooltip: 'Add row',
                iconSize: 18,
                icon: const Icon(Icons.add_box_outlined),
                onPressed: () => _c.addTableRow(node.id),
              ),
              IconButton(
                key: Key('markey-table-addcol-${node.id}'),
                tooltip: 'Add column',
                iconSize: 18,
                icon: const Icon(Icons.add_box),
                onPressed: () => _c.addTableColumn(node.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cellContent(TableNode table, int r, int c, EditorStyle style) {
    final delta = table.rows[r][c];
    final base = r == 0
        ? style.baseTextStyle.copyWith(fontWeight: FontWeight.bold)
        : style.baseTextStyle;
    final sel = _c.selection;
    TextSelection? localSelection;
    int? caretOffset;
    if (sel != null) {
      final bp = sel.base.nodePosition;
      final ep = sel.extent.nodePosition;
      final baseHere = sel.base.nodeId == table.id &&
          bp is TableCellPosition &&
          bp.row == r &&
          bp.col == c;
      final extHere = sel.extent.nodeId == table.id &&
          ep is TableCellPosition &&
          ep.row == r &&
          ep.col == c;
      if (baseHere && extHere) {
        final b = bp.offset;
        final e = ep.offset;
        if (b == e) {
          caretOffset = b;
        } else {
          localSelection = TextSelection(baseOffset: b, extentOffset: e);
        }
      }
    }
    final showCaret = _focusNode.hasFocus && caretOffset != null;
    final cacheKey = '${table.id}:$r:$c';
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tp = _layoutForCellDelta(cacheKey, delta, base, width);
        final height = math.max(tp.height, base.fontSize ?? 16);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _placeCellCaret(table.id, r, c, d.localPosition, tp),
          child: CustomPaint(
            key: Key('markey-cell-${table.id}-$r-$c'),
            size: Size(width, height),
            painter: _BlockPainter(
              textPainter: tp,
              selection: localSelection,
              caretOffset: caretOffset,
              showCaret: showCaret,
              caretBlink: _caretBlink,
              selectionColor: style.selectionColor,
              caretColor: style.caretColor,
            ),
          ),
        );
      },
    );
  }

  TextPainter _layoutForCellDelta(
      String cacheKey, Delta delta, TextStyle base, double width) {
    final cached = _layoutCache[cacheKey];
    if (cached != null &&
        cached.width == width &&
        identical(cached.contentKey, delta) &&
        cached.styleVersion == _styleVersion) {
      return cached.painter;
    }
    cached?.painter.dispose();
    final span = deltaToTextSpan(delta, base, _resolveStyle()) as TextSpan;
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout(maxWidth: width);
    _layoutCache[cacheKey] = _CachedLayout(width, delta, painter, _styleVersion);
    return painter;
  }

  void _placeCellCaret(
      String tableId, int r, int c, Offset localPos, TextPainter tp) {
    if (widget.readOnly) return;
    _focusNode.requestFocus();
    final off = tp.getPositionForOffset(localPos).offset;
    _c.placeCaretAt(DocumentPosition(
        nodeId: tableId, nodePosition: TableCellPosition(r, c, off)));
  }

  Widget _buildMath(MathBlockNode node, EditorStyle style) {
    return Container(
      key: ValueKey('markey-block-${node.id}'),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Math.tex(
        node.tex,
        mathStyle: MathStyle.display,
        textStyle: style.baseTextStyle,
        onErrorFallback: (e) =>
            Text(node.tex, style: style.codeTextStyle.copyWith(backgroundColor: null)),
      ),
    );
  }

  Widget _buildImage(ImageNode node, EditorStyle style) {
    return Align(
      key: ValueKey('markey-block-${node.id}'),
      alignment: Alignment.centerLeft,
      child: Image.network(
        node.url,
        errorBuilder: (context, error, stack) => Container(
          padding: const EdgeInsets.all(8),
          color: style.codeTextStyle.backgroundColor,
          child: Text(
            node.alt?.isNotEmpty == true ? '🖼 ${node.alt}' : '🖼 image',
            style: style.baseTextStyle,
          ),
        ),
      ),
    );
  }

  Widget _buildFrontMatter(FrontMatterNode node, EditorStyle style) {
    final mono = style.codeTextStyle.copyWith(backgroundColor: null);
    return Container(
      key: ValueKey('markey-frontmatter-${node.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.codeTextStyle.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: style.caretColor.withValues(alpha: 0.4), width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('front matter',
              style: mono.copyWith(
                fontSize: (mono.fontSize ?? 14) * 0.8,
                color: style.caretColor.withValues(alpha: 0.6),
              )),
          const SizedBox(height: 4),
          Text(node.yaml, style: mono),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(CodeBlockNode node, EditorStyle style) {
    final codeStyle = style.codeTextStyle.copyWith(backgroundColor: null);
    return Container(
      key: ValueKey('markey-code-${node.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.codeTextStyle.backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (node.language != null && node.language!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                node.language!,
                style: codeStyle.copyWith(
                  fontSize: (codeStyle.fontSize ?? 14) * 0.8,
                  color: style.caretColor.withValues(alpha: 0.6),
                ),
              ),
            ),
          // Read-only: highlighted display. Editable: unified caret/selection so
          // the code block is part of the one editor (not a separate field).
          if (widget.readOnly)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: RichText(
                  text: TextSpan(
                      children: _highlighter.highlight(
                          node.code, node.language, codeStyle))),
            )
          else
            _codeContent(node, style),
        ],
      ),
    );
  }

  /// Editable code content with the unified caret/selection (mirrors
  /// [_textContent] but over the highlighted code; edits route through the same
  /// command pipeline via the document stream).
  Widget _codeContent(CodeBlockNode node, EditorStyle style) {
    final sel = _c.selection;
    TextSelection? localSelection;
    int? caretOffset;
    if (sel != null &&
        sel.base.nodeId == node.id &&
        sel.extent.nodeId == node.id) {
      final b = (sel.base.nodePosition as TextNodePosition).offset;
      final e = (sel.extent.nodePosition as TextNodePosition).offset;
      if (b == e) {
        caretOffset = b;
      } else {
        localSelection = TextSelection(baseOffset: b, extentOffset: e);
      }
    } else if (sel != null && !sel.isCollapsed) {
      localSelection = _crossBlockLocalSelection(node, sel);
    }
    final showCaret = _focusNode.hasFocus && caretOffset != null;
    return LayoutBuilder(
      key: ValueKey('markey-block-${node.id}'),
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _lastBlockWidth = width;
        final layout = _codeLayoutFor(node, width);
        final height =
            math.max(layout.height, style.codeTextStyle.fontSize ?? 16);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _placeCaret(node, d.localPosition, width),
          onPanStart: (d) {
            if (_mouseSelecting) return;
            _placeCaret(node, d.localPosition, width);
          },
          onPanUpdate: (d) {
            if (_mouseSelecting) return;
            _extendSelectionGlobal(node, d, width);
          },
          child: CustomPaint(
            key: _paintKeyFor(node.id),
            size: Size(width, height),
            painter: _CodeBlockPainter(
              layout: layout,
              selectionStart: localSelection?.start,
              selectionEnd: localSelection?.end,
              caretOffset: caretOffset,
              showCaret: showCaret,
              caretBlink: _caretBlink,
              selectionColor: style.selectionColor,
              caretColor: style.caretColor,
            ),
          ),
        );
      },
    );
  }

  /// The portion of a cross-block [sel] that falls within [node], as a local
  /// [TextSelection], or null when [node] lies outside the selected range.
  TextSelection? _crossBlockLocalSelection(Node node, DocumentSelection sel) {
    final doc = _c.document;
    final iBase = doc.indexOfId(sel.base.nodeId);
    final iExt = doc.indexOfId(sel.extent.nodeId);
    final iNode = doc.indexOfId(node.id);
    if (iBase < 0 || iExt < 0 || iNode < 0) return null;
    final startIdx = math.min(iBase, iExt);
    final endIdx = math.max(iBase, iExt);
    if (iNode < startIdx || iNode > endIdx) return null;
    final startPos = iBase <= iExt ? sel.base : sel.extent;
    final endPos = iBase <= iExt ? sel.extent : sel.base;
    int offsetOf(DocumentPosition p) =>
        p.nodePosition is TextNodePosition
            ? (p.nodePosition as TextNodePosition).offset
            : 0;
    final len = node is CodeBlockNode
        ? node.code.length
        : (node as TextBlockNode).delta.length;
    final from = iNode == startIdx ? offsetOf(startPos) : 0;
    final to = iNode == endIdx ? offsetOf(endPos) : len;
    return TextSelection(baseOffset: from, extentOffset: to);
  }

  Widget _textContent(TextBlockNode node, EditorStyle style) {
    final base = baseStyleFor(node, style);
    final sel = _c.selection;

    TextSelection? localSelection;
    int? caretOffset;
    if (sel != null && sel.base.nodeId == node.id && sel.extent.nodeId == node.id) {
      final b = (sel.base.nodePosition as TextNodePosition).offset;
      final e = (sel.extent.nodePosition as TextNodePosition).offset;
      if (b == e) {
        caretOffset = b;
      } else {
        localSelection = TextSelection(baseOffset: b, extentOffset: e);
      }
    } else if (sel != null && !sel.isCollapsed) {
      localSelection = _crossBlockLocalSelection(node, sel);
    }
    final showCaret = _focusNode.hasFocus && caretOffset != null;

    return Directionality(
      // Per-paragraph base direction so RTL scripts align right and child
      // affordances (bullets, checkboxes) follow; the painter uses the same.
      textDirection: resolveBaseDirection(node.delta.toPlainText()),
      child: LayoutBuilder(
      key: ValueKey('markey-block-${node.id}'),
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        _lastBlockWidth = width;
        final tp = _layoutFor(node, width); // cached: no re-shape if unchanged
        final height = math.max(tp.height, base.fontSize ?? 16);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _placeCaret(node, d.localPosition, width),
          // While a precise-pointer drag is in progress the root Listener owns
          // selection (across blocks); don't let the per-block pan clobber it.
          onPanStart: (d) {
            if (_mouseSelecting) return;
            _placeCaret(node, d.localPosition, width);
          },
          onPanUpdate: (d) {
            if (_mouseSelecting) return;
            _extendSelectionGlobal(node, d, width);
          },
          child: CustomPaint(
            key: _paintKeyFor(node.id),
            size: Size(width, height),
            painter: _BlockPainter(
              textPainter: tp,
              selection: localSelection,
              caretOffset: caretOffset,
              showCaret: showCaret,
              caretBlink: _caretBlink,
              selectionColor: style.selectionColor,
              caretColor: style.caretColor,
            ),
          ),
        );
      },
      ),
    );
  }

  Map<ShortcutActivator, Intent> _shortcuts() {
    final meta = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: meta, control: !meta, shift: shift);
    return {
      cmd(LogicalKeyboardKey.keyB): const _ToggleMarkIntent('bold'),
      cmd(LogicalKeyboardKey.keyI): const _ToggleMarkIntent('italic'),
      cmd(LogicalKeyboardKey.keyZ): const _UndoIntent(),
      cmd(LogicalKeyboardKey.keyZ, shift: true): const _RedoIntent(),
      cmd(LogicalKeyboardKey.keyF): const _FindIntent(),
      cmd(LogicalKeyboardKey.keyV): const _PasteIntent(),
      cmd(LogicalKeyboardKey.keyV, shift: true): const _PastePlainIntent(),
      cmd(LogicalKeyboardKey.keyC): const _CopyIntent(),
      cmd(LogicalKeyboardKey.keyX): const _CutIntent(),
      cmd(LogicalKeyboardKey.keyA): const _SelectAllIntent(),
      // Block reorder keeps Alt/Opt+Up/Down (a markey_mark affordance).
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
          const _MoveBlockIntent(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
          const _MoveBlockIntent(1),
      const SingleActivator(LogicalKeyboardKey.escape): const _DismissSlashIntent(),
      ..._caretShortcuts(meta),
      ..._deleteShortcuts(meta),
    };
  }

  /// Word/line deletion (Alt+Backspace/Delete on macOS, Ctrl elsewhere; plus
  /// Cmd+Backspace delete-to-line-start on macOS), the destructive counterpart
  /// of the word/line caret moves.
  Map<ShortcutActivator, Intent> _deleteShortcuts(bool meta) => {
        SingleActivator(LogicalKeyboardKey.backspace,
                alt: meta, control: !meta):
            const _DeleteIntent(false, CaretGranularity.word),
        SingleActivator(LogicalKeyboardKey.delete, alt: meta, control: !meta):
            const _DeleteIntent(true, CaretGranularity.word),
        if (meta)
          const SingleActivator(LogicalKeyboardKey.backspace, meta: true):
              const _DeleteIntent(false, CaretGranularity.lineBoundary),
      };

  /// Platform-aware caret/selection key bindings, modelled on Flutter's
  /// `DefaultTextEditingShortcuts` (char/word/line/document × collapse/extend ×
  /// horizontal/vertical), generalized to our multi-block document.
  Map<ShortcutActivator, Intent> _caretShortcuts(bool meta) {
    final m = <ShortcutActivator, Intent>{};
    for (final shift in const [false, true]) {
      // Character left/right.
      m[SingleActivator(LogicalKeyboardKey.arrowLeft, shift: shift)] =
          _MoveIntent(false, CaretGranularity.character, shift);
      m[SingleActivator(LogicalKeyboardKey.arrowRight, shift: shift)] =
          _MoveIntent(true, CaretGranularity.character, shift);
      // Vertical line up/down (goal column preserved).
      m[SingleActivator(LogicalKeyboardKey.arrowUp, shift: shift)] =
          _VerticalMoveIntent(false, shift);
      m[SingleActivator(LogicalKeyboardKey.arrowDown, shift: shift)] =
          _VerticalMoveIntent(true, shift);
      // Word-wise: Alt+arrow on macOS, Ctrl+arrow elsewhere.
      m[SingleActivator(LogicalKeyboardKey.arrowLeft,
              shift: shift, alt: meta, control: !meta)] =
          _MoveIntent(false, CaretGranularity.word, shift);
      m[SingleActivator(LogicalKeyboardKey.arrowRight,
              shift: shift, alt: meta, control: !meta)] =
          _MoveIntent(true, CaretGranularity.word, shift);
      // Line boundary: Cmd+arrow on macOS, Home/End elsewhere.
      m[SingleActivator(LogicalKeyboardKey.home, shift: shift)] =
          _MoveIntent(false, CaretGranularity.lineBoundary, shift);
      m[SingleActivator(LogicalKeyboardKey.end, shift: shift)] =
          _MoveIntent(true, CaretGranularity.lineBoundary, shift);
      if (meta) {
        m[SingleActivator(LogicalKeyboardKey.arrowLeft,
                shift: shift, meta: true)] =
            _MoveIntent(false, CaretGranularity.lineBoundary, shift);
        m[SingleActivator(LogicalKeyboardKey.arrowRight,
                shift: shift, meta: true)] =
            _MoveIntent(true, CaretGranularity.lineBoundary, shift);
        // Document boundary: Cmd+Up/Down on macOS.
        m[SingleActivator(LogicalKeyboardKey.arrowUp, shift: shift, meta: true)] =
            _MoveIntent(false, CaretGranularity.documentBoundary, shift);
        m[SingleActivator(LogicalKeyboardKey.arrowDown,
                shift: shift, meta: true)] =
            _MoveIntent(true, CaretGranularity.documentBoundary, shift);
      } else {
        // Document boundary: Ctrl+Home/End elsewhere.
        m[SingleActivator(LogicalKeyboardKey.home, shift: shift, control: true)] =
            _MoveIntent(false, CaretGranularity.documentBoundary, shift);
        m[SingleActivator(LogicalKeyboardKey.end, shift: shift, control: true)] =
            _MoveIntent(true, CaretGranularity.documentBoundary, shift);
      }
    }
    return m;
  }

  Map<Type, Action<Intent>> _actions() => {
        _ToggleMarkIntent: CallbackAction<_ToggleMarkIntent>(
          onInvoke: (i) {
            _c.toggleMark(i.mark);
            return null;
          },
        ),
        _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) {
          _c.undo();
          return null;
        }),
        _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) {
          _c.redo();
          return null;
        }),
        _MoveIntent: CallbackAction<_MoveIntent>(onInvoke: (i) {
          _verticalGoalX = null; // any horizontal/word/line move ends a v-run
          _c.moveSelection(
              forward: i.forward, granularity: i.granularity, extend: i.extend);
          return null;
        }),
        _VerticalMoveIntent: CallbackAction<_VerticalMoveIntent>(onInvoke: (i) {
          _moveCaretVertical(forward: i.forward, extend: i.extend);
          return null;
        }),
        _DeleteIntent: CallbackAction<_DeleteIntent>(onInvoke: (i) {
          if (!widget.readOnly) {
            _verticalGoalX = null;
            _c.deleteByGranularity(
                forward: i.forward, granularity: i.granularity);
          }
          return null;
        }),
        _DismissSlashIntent: CallbackAction<_DismissSlashIntent>(onInvoke: (_) {
          if (_activeSlashQuery() != null) {
            setState(() => _slashSuppressed = true);
          }
          return null;
        }),
        _FindIntent: CallbackAction<_FindIntent>(onInvoke: (_) {
          _openFind();
          return null;
        }),
        _PasteIntent: CallbackAction<_PasteIntent>(onInvoke: (_) {
          _handlePaste();
          return null;
        }),
        _PastePlainIntent: CallbackAction<_PastePlainIntent>(onInvoke: (_) {
          if (!widget.readOnly) _c.pastePlain(bridge: widget.clipboard);
          return null;
        }),
        _SelectAllIntent: CallbackAction<_SelectAllIntent>(onInvoke: (_) {
          _c.selectAll();
          return null;
        }),
        _CopyIntent: CallbackAction<_CopyIntent>(onInvoke: (_) {
          _handleCopy();
          return null;
        }),
        _CutIntent: CallbackAction<_CutIntent>(onInvoke: (_) {
          _handleCut();
          return null;
        }),
        _MoveBlockIntent: CallbackAction<_MoveBlockIntent>(onInvoke: (i) {
          final id = _c.selection?.extent.nodeId;
          if (id != null) {
            i.dir < 0 ? _c.moveBlockUp(id) : _c.moveBlockDown(id);
          }
          return null;
        }),
      };
}

// ── Intents ──────────────────────────────────────────────────────────────

class _ToggleMarkIntent extends Intent {
  const _ToggleMarkIntent(this.mark);
  final String mark;
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _DismissSlashIntent extends Intent {
  const _DismissSlashIntent();
}

class _FindIntent extends Intent {
  const _FindIntent();
}

class _MoveBlockIntent extends Intent {
  const _MoveBlockIntent(this.dir);
  final int dir;
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _PastePlainIntent extends Intent {
  const _PastePlainIntent();
}

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _CutIntent extends Intent {
  const _CutIntent();
}

/// Horizontal / word / line / document caret movement (collapse when [extend]
/// is false, extend the selection when true).
class _MoveIntent extends Intent {
  const _MoveIntent(this.forward, this.granularity, this.extend);
  final bool forward;
  final CaretGranularity granularity;
  final bool extend;
}

/// Vertical (line up/down) caret movement, preserving the goal column.
class _VerticalMoveIntent extends Intent {
  const _VerticalMoveIntent(this.forward, this.extend);
  final bool forward;
  final bool extend;
}

/// Word / line deletion in a direction (Ctrl/Alt+Backspace etc.).
class _DeleteIntent extends Intent {
  const _DeleteIntent(this.forward, this.granularity);
  final bool forward;
  final CaretGranularity granularity;
}

// ── Source-mode highlighting controller ────────────────────────────────────

/// A [TextEditingController] that renders the raw Markdown source with native
/// syntax highlighting (no WebView/JS).
class _MarkdownSourceController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    return TextSpan(style: base, children: markdownSourceSpans(text, base));
  }
}

// ── Painter ────────────────────────────────────────────────────────────────

/// A cached, laid-out block text layout (see `_MarkdownEditorState._layoutFor`).
class _CachedLayout {
  _CachedLayout(this.width, this.contentKey, this.painter, this.styleVersion);
  final double width;
  // Delta (identity) for text blocks, or the code String for code blocks.
  final Object contentKey;
  final TextPainter painter;
  final int styleVersion;
}

/// Wraps a block with a hover-revealed drag handle (a [Draggable] of the block
/// index) and makes the block a [DragTarget], so blocks can be reordered by
/// dragging the handle. The handle sits in a narrow left gutter, outside the
/// block's text-hit area, so it doesn't interfere with caret/selection.
class _ReorderableBlock extends StatefulWidget {
  const _ReorderableBlock({
    required this.index,
    required this.handleKey,
    required this.onReorder,
    required this.accent,
    required this.child,
  });

  final int index;
  final Key handleKey;
  final void Function(int from, int to) onReorder;
  final Color accent;
  final Widget child;

  @override
  State<_ReorderableBlock> createState() => _ReorderableBlockState();
}

class _ReorderableBlockState extends State<_ReorderableBlock> {
  bool _hovering = false;
  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    final handle = MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Draggable<int>(
        key: widget.handleKey,
        data: widget.index,
        affinity: Axis.vertical,
        feedback: Material(
          color: Colors.transparent,
          child: Icon(Icons.drag_indicator, color: widget.accent),
        ),
        child: Opacity(
          opacity: _hovering ? 0.7 : 0.25,
          child: Icon(Icons.drag_indicator,
              size: 18, color: widget.accent.withValues(alpha: 0.8)),
        ),
      ),
    );

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != widget.index,
      onAcceptWithDetails: (d) => widget.onReorder(d.data, widget.index),
      onMove: (_) => setState(() => _dragOver = true),
      onLeave: (_) => setState(() => _dragOver = false),
      builder: (context, _, __) => Container(
        decoration: _dragOver
            ? BoxDecoration(
                border: Border(
                    top: BorderSide(color: widget.accent, width: 2)))
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: SizedBox(width: 20, child: handle),
            ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

class _BlockPainter extends CustomPainter {
  _BlockPainter({
    required this.textPainter,
    required this.selection,
    required this.caretOffset,
    required this.showCaret,
    required this.caretBlink,
    required this.selectionColor,
    required this.caretColor,
  }) : super(repaint: caretBlink);

  /// Pre-laid-out; the painter never re-shapes (caret blink only repaints).
  final TextPainter textPainter;
  final TextSelection? selection;
  final int? caretOffset;
  final bool showCaret;
  final ValueListenable<bool> caretBlink;
  final Color selectionColor;
  final Color caretColor;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = textPainter;

    if (selection != null && !selection!.isCollapsed) {
      final boxes = tp.getBoxesForSelection(selection!);
      final paint = Paint()..color = selectionColor;
      for (final box in boxes) {
        canvas.drawRect(box.toRect(), paint);
      }
    }

    tp.paint(canvas, Offset.zero);

    if (showCaret && caretOffset != null && caretBlink.value) {
      final pos = TextPosition(offset: caretOffset!);
      final caretOff = tp.getOffsetForCaret(pos, Rect.zero);
      final height = tp.getFullHeightForCaret(pos, Rect.zero);
      canvas.drawRect(
        Rect.fromLTWH(caretOff.dx, caretOff.dy, 2, height),
        Paint()..color = caretColor,
      );
    }
  }

  @override
  bool shouldRepaint(_BlockPainter old) =>
      !identical(old.textPainter, textPainter) ||
      old.selection != selection ||
      old.caretOffset != caretOffset ||
      old.showCaret != showCaret ||
      old.selectionColor != selectionColor ||
      old.caretColor != caretColor;
}

/// Paints a code block from its per-line [CodeLayout] (caret blink only
/// repaints; the layout never re-shapes here). Selection/caret offsets are
/// char offsets into the block's code string.
class _CodeBlockPainter extends CustomPainter {
  _CodeBlockPainter({
    required this.layout,
    required this.selectionStart,
    required this.selectionEnd,
    required this.caretOffset,
    required this.showCaret,
    required this.caretBlink,
    required this.selectionColor,
    required this.caretColor,
  }) : super(repaint: caretBlink);

  final CodeLayout layout;
  final int? selectionStart;
  final int? selectionEnd;
  final int? caretOffset;
  final bool showCaret;
  final ValueListenable<bool> caretBlink;
  final Color selectionColor;
  final Color caretColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (selectionStart != null &&
        selectionEnd != null &&
        selectionStart != selectionEnd) {
      final paint = Paint()..color = selectionColor;
      for (final rect in layout.getBoxesForSelection(
          selectionStart!, selectionEnd!)) {
        canvas.drawRect(rect, paint);
      }
    }

    layout.paint(canvas, Offset.zero);

    if (showCaret && caretOffset != null && caretBlink.value) {
      final off = layout.getOffsetForCaret(caretOffset!);
      final height = layout.getFullHeightForCaret(caretOffset!);
      canvas.drawRect(
        Rect.fromLTWH(off.dx, off.dy, 2, height),
        Paint()..color = caretColor,
      );
    }
  }

  @override
  bool shouldRepaint(_CodeBlockPainter old) =>
      !identical(old.layout, layout) ||
      old.selectionStart != selectionStart ||
      old.selectionEnd != selectionEnd ||
      old.caretOffset != caretOffset ||
      old.showCaret != showCaret ||
      old.selectionColor != selectionColor ||
      old.caretColor != caretColor;
}

// ── Selection bubble toolbar ───────────────────────────────────────────────

/// A compact floating toolbar shown over a text selection (Medium/Google-Docs
/// style) for quick inline formatting.
class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({required this.controller});
  final MarkdownEditorController controller;

  @override
  Widget build(BuildContext context) {
    Widget btn(String key, IconData icon, String mark, String tip) => IconButton(
          key: Key('markey_bubble_$key'),
          tooltip: tip,
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon),
          onPressed: () => controller.toggleMark(mark),
        );
    return Material(
      key: const Key('markey_bubble'),
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn('bold', Icons.format_bold, 'bold', 'Bold'),
            btn('italic', Icons.format_italic, 'italic', 'Italic'),
            btn('strike', Icons.format_strikethrough, 'strike', 'Strikethrough'),
            btn('highlight', Icons.highlight, 'highlight', 'Highlight'),
            btn('code', Icons.code, 'code', 'Inline code'),
          ],
        ),
      ),
    );
  }
}

// ── Toolbar ────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});
  final MarkdownEditorController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isSource = controller.mode == EditorMode.source;
        return Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            // Responsive: the formatting buttons scroll horizontally on narrow
            // screens (mobile) so the bar never overflows; the mode toggle stays
            // pinned at the trailing edge.
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('markey_undo'),
                          tooltip: 'Undo',
                          icon: const Icon(Icons.undo),
                          onPressed: controller.canUndo ? controller.undo : null,
                        ),
                        IconButton(
                          key: const Key('markey_redo'),
                          tooltip: 'Redo',
                          icon: const Icon(Icons.redo),
                          onPressed: controller.canRedo ? controller.redo : null,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: const Key('markey_bold'),
                          tooltip: 'Bold',
                          icon: const Icon(Icons.format_bold),
                          onPressed: isSource
                              ? null
                              : () => controller.toggleMark('bold'),
                        ),
                        IconButton(
                          key: const Key('markey_italic'),
                          tooltip: 'Italic',
                          icon: const Icon(Icons.format_italic),
                          onPressed: isSource
                              ? null
                              : () => controller.toggleMark('italic'),
                        ),
                        IconButton(
                          key: const Key('markey_h1'),
                          tooltip: 'Heading 1',
                          icon: const Icon(Icons.title),
                          onPressed: isSource
                              ? null
                              : () => controller.setBlockType(
                                  BlockType.heading,
                                  level: 1),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('markey_toggle_mode'),
                  tooltip: isSource ? 'Rich text' : 'Markdown source',
                  icon: Icon(isSource ? Icons.visibility : Icons.code),
                  onPressed: controller.toggleMode,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
