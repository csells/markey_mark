import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../editing/search.dart';
import '../model/attributes.dart';
import '../model/delta.dart';
import '../model/node.dart';
import '../model/position.dart';
import '../model/selection.dart';
import '../render/code_highlight.dart';
import '../render/delta_text.dart';
import '../render/diagram_renderer.dart';
import '../render/markdown_source_highlight.dart';
import '../theme/editor_style.dart';
import '../ui/slash_menu.dart';
import 'controller.dart';

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

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> with TextInputClient {
  late FocusNode _focusNode;
  final _MarkdownSourceController _sourceController = _MarkdownSourceController();
  final ValueNotifier<bool> _caretBlink = ValueNotifier<bool>(false);
  Timer? _blinkTimer;

  TextInputConnection? _connection;
  TextEditingValue _imeValue = TextEditingValue.empty;

  /// Per-block laid-out text, keyed by node id (see [_layoutFor]).
  final Map<String, _CachedLayout> _layoutCache = {};

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

  EditorStyle _resolveStyle() =>
      widget.style ?? EditorStyle.fromTheme(Theme.of(context));

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _lastDoc = _c.document;
    _c.addListener(_onControllerChanged);
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
    _disposeLayoutCache();
    super.dispose();
  }

  Object? _lastDoc;

  void _onControllerChanged() {
    // Fire onChanged only when the (immutable) document actually changed.
    if (widget.onChanged != null && !identical(_lastDoc, _c.document)) {
      _lastDoc = _c.document;
      widget.onChanged!(_c.markdown);
    }
    // Re-arm the slash menu once the `/` query is gone.
    if (_activeSlashQuery() == null) _slashSuppressed = false;
    if (mounted) setState(_syncImeFromModel);
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

  /// Returns a laid-out [TextPainter] for [node] at [width], reusing the cache
  /// unless the block's (immutable) delta or the width changed. Text shaping is
  /// the dominant cost; this keeps a steady-state edit to one layout per frame
  /// for the edited block and zero for the rest.
  TextPainter _layoutFor(TextBlockNode node, double width) {
    final style = _resolveStyle();
    final cached = _layoutCache[node.id];
    if (cached != null &&
        cached.width == width &&
        identical(cached.delta, node.delta) &&
        cached.styleVersion == _styleVersion) {
      return cached.painter;
    }
    cached?.painter.dispose();
    final base = baseStyleFor(node, style);
    final span = deltaToTextSpan(node.delta, base, style);
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout(maxWidth: width);
    _layoutCache[node.id] =
        _CachedLayout(width, node.delta, painter, _styleVersion);
    return painter;
  }

  void _disposeLayoutCache() {
    for (final c in _layoutCache.values) {
      c.painter.dispose();
    }
    _layoutCache.clear();
  }

  /// Bumped when the resolved style changes so cached layouts invalidate.
  int get _styleVersion => _resolveStyle().hashCode;

  // ── Active block + IME sync ──────────────────────────────────────────────

  TextBlockNode? get _activeBlock {
    final sel = _c.selection;
    final id = sel?.extent.nodeId;
    final node = id != null ? _c.document.nodeById(id) : null;
    if (node is TextBlockNode) return node;
    final first = _c.document.nodes.first;
    return first is TextBlockNode ? first : null;
  }

  void _syncImeFromModel() {
    final block = _activeBlock;
    if (block == null) return;
    final text = block.delta.toPlainText();
    final sel = _c.selection;
    var base = text.length;
    var extent = text.length;
    if (sel != null &&
        sel.base.nodeId == block.id &&
        sel.extent.nodeId == block.id) {
      base = (sel.base.nodePosition as TextNodePosition).offset;
      extent = (sel.extent.nodePosition as TextNodePosition).offset;
    }
    _imeValue = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: base.clamp(0, text.length),
        extentOffset: extent.clamp(0, text.length),
      ),
    );
    _connection?.setEditingState(_imeValue);
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
    final block = _activeBlock;
    if (block == null) {
      _imeValue = value;
      return;
    }
    final old = _imeValue.text;
    if (value.text == old) {
      // Selection-only change.
      final s = value.selection;
      if (s.isValid) {
        _c.setSelection(DocumentSelection(
          base: DocumentPosition.text(block.id, s.baseOffset),
          extent: DocumentPosition.text(block.id, s.extentOffset),
        ));
      }
      _imeValue = value;
      return;
    }

    final (start, deleted, inserted) = _diff(old, value.text);
    _c.setSelection(DocumentSelection(
      base: DocumentPosition.text(block.id, start),
      extent: DocumentPosition.text(block.id, start + deleted),
    ));
    if (inserted.isEmpty) {
      _c.deleteBackward();
    } else if (inserted == '\n') {
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
    // Model change triggers _onControllerChanged → _syncImeFromModel.
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

  // ── Gestures ─────────────────────────────────────────────────────────────

  void _placeCaret(TextBlockNode node, Offset localPos, double width) {
    if (widget.readOnly) return;
    final tp = _layoutFor(node, width);
    final pos = tp.getPositionForOffset(localPos);
    _focusNode.requestFocus();
    _c.setSelection(DocumentSelection.collapsed(
      DocumentPosition.text(node.id, pos.offset),
    ));
  }

  void _extendSelection(TextBlockNode node, Offset localPos, double width) {
    if (widget.readOnly) return;
    final tp = _layoutFor(node, width);
    final pos = tp.getPositionForOffset(localPos);
    final sel = _c.selection;
    final base = (sel != null && sel.base.nodeId == node.id)
        ? sel.base
        : DocumentPosition.text(node.id, pos.offset);
    _c.setSelection(DocumentSelection(
      base: base,
      extent: DocumentPosition.text(node.id, pos.offset),
    ));
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
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _c.pasteMarkdown(text);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final style = _resolveStyle();
    final body = _c.mode == EditorMode.source ? _buildSource() : _buildWysiwyg();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToolbar) _Toolbar(controller: _c),
        if (_showFind && _c.mode == EditorMode.wysiwyg) _buildFindBar(style),
        Expanded(child: body),
      ],
    );
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
    _sourceController.value = TextEditingValue(
      text: _c.markdown,
      selection: _sourceController.selection.isValid &&
              _sourceController.selection.end <= _c.markdown.length
          ? _sourceController.selection
          : TextSelection.collapsed(offset: _c.markdown.length),
    );
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

  Widget _buildWysiwyg() {
    final style = _resolveStyle();
    final slashQuery = _slashSuppressed ? null : _activeSlashQuery();
    return Shortcuts(
      shortcuts: _shortcuts(),
      child: Actions(
        actions: _actions(),
        child: Focus(
          focusNode: _focusNode,
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _focusNode.requestFocus,
                child: ListView.separated(
                  padding: style.padding,
                  itemCount: _c.document.nodes.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(height: style.blockSpacing),
                  itemBuilder: (context, index) {
                    final node = _c.document.nodes[index];
                    if (node is CodeBlockNode) {
                      return _buildCodeBlock(node, style);
                    }
                    if (node is HorizontalRuleNode) return _buildHr(node, style);
                    if (node is ImageNode) {
                      return Semantics(
                        image: true,
                        excludeSemantics: true,
                        label: (node.alt == null || node.alt!.isEmpty)
                            ? 'image'
                            : node.alt,
                        child: _buildImage(node, style),
                      );
                    }
                    if (node is MathBlockNode) return _buildMath(node, style);
                    if (node is TableNode) {
                      return widget.readOnly
                          ? _buildTable(node, style)
                          : _EditableTable(
                              node: node, style: style, controller: _c);
                    }
                    if (node is MermaidNode) {
                      return widget.diagramRenderer.build(context, node, style);
                    }
                    if (node is FrontMatterNode) {
                      return _buildFrontMatter(node, style);
                    }
                    if (node is TextBlockNode) {
                      return Semantics(
                        header: node.type == BlockType.heading,
                        label: node.delta.toPlainText(),
                        child: _buildBlock(node, style),
                      );
                    }
                    return const SizedBox.shrink();
                  },
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

  Widget _gutterRow(Widget marker, Widget content) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(right: 8), child: marker),
          Expanded(child: content),
        ],
      );

  Widget _marker(String text, EditorStyle style) =>
      Text(text, style: style.baseTextStyle);

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
    final spans = _highlighter.highlight(node.code, node.language, codeStyle);
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: RichText(text: TextSpan(children: spans)),
          ),
        ],
      ),
    );
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
    }
    final showCaret = _focusNode.hasFocus && caretOffset != null;

    return LayoutBuilder(
      key: ValueKey('markey-block-${node.id}'),
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final tp = _layoutFor(node, width); // cached: no re-shape if unchanged
        final height = math.max(tp.height, base.fontSize ?? 16);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _placeCaret(node, d.localPosition, width),
          onPanStart: (d) => _placeCaret(node, d.localPosition, width),
          onPanUpdate: (d) => _extendSelection(node, d.localPosition, width),
          child: CustomPaint(
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
      const SingleActivator(LogicalKeyboardKey.arrowLeft):
          const _MoveCaretIntent(false),
      const SingleActivator(LogicalKeyboardKey.arrowRight):
          const _MoveCaretIntent(true),
      const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
          const _MoveBlockIntent(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
          const _MoveBlockIntent(1),
      const SingleActivator(LogicalKeyboardKey.escape): const _DismissSlashIntent(),
    };
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
        _MoveCaretIntent: CallbackAction<_MoveCaretIntent>(onInvoke: (i) {
          if (i.forward) {
            _c.moveCaretRight();
          } else {
            _c.moveCaretLeft();
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

class _MoveCaretIntent extends Intent {
  const _MoveCaretIntent(this.forward);
  final bool forward;
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
  _CachedLayout(this.width, this.delta, this.painter, this.styleVersion);
  final double width;
  final Delta delta;
  final TextPainter painter;
  final int styleVersion;
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

// ── Editable table ─────────────────────────────────────────────────────────

TextAlign _tableTextAlign(TableAlign a) => switch (a) {
      TableAlign.center => TextAlign.center,
      TableAlign.right => TextAlign.right,
      _ => TextAlign.left,
    };

/// An editable GFM table: each cell is a [TextField] writing back to the model;
/// buttons append rows/columns. Cell controllers persist across rebuilds so the
/// caret is stable while typing.
class _EditableTable extends StatefulWidget {
  const _EditableTable(
      {required this.node, required this.style, required this.controller});
  final TableNode node;
  final EditorStyle style;
  final MarkdownEditorController controller;

  @override
  State<_EditableTable> createState() => _EditableTableState();
}

class _EditableTableState extends State<_EditableTable> {
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, FocusNode> _fn = {};

  String _key(int r, int c) => '${r}_$c';

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final f in _fn.values) {
      f.dispose();
    }
    super.dispose();
  }

  TextEditingController _cellController(int r, int c) {
    final k = _key(r, c);
    final text = widget.controller.cellMarkdown(widget.node.id, r, c);
    final ctl = _ctl.putIfAbsent(k, () => TextEditingController(text: text));
    final fn = _fn.putIfAbsent(k, () => FocusNode());
    if (!fn.hasFocus && ctl.text != text) ctl.text = text;
    return ctl;
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final style = widget.style;
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
                            horizontal: 6, vertical: 2),
                        child: TextField(
                          key: Key('markey-cell-${node.id}-$r-$c'),
                          controller: _cellController(r, c),
                          focusNode: _fn[_key(r, c)],
                          textAlign: _tableTextAlign(node.alignments[c]),
                          style: r == 0
                              ? style.baseTextStyle
                                  .copyWith(fontWeight: FontWeight.bold)
                              : style.baseTextStyle,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                          ),
                          onChanged: (t) =>
                              widget.controller.updateTableCell(node.id, r, c, t),
                        ),
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
                onPressed: () => widget.controller.addTableRow(node.id),
              ),
              IconButton(
                key: Key('markey-table-addcol-${node.id}'),
                tooltip: 'Add column',
                iconSize: 18,
                icon: const Icon(Icons.add_box),
                onPressed: () => widget.controller.addTableColumn(node.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
