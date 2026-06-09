part of '../markdown_editor.dart';

// Standalone view classes for MarkdownEditor (painters, chrome widgets, the
// text-field-semantics render object, source-mode controller, reorderable-block
// wrapper) — split out of markdown_editor.dart to shrink that file. Privacy is
// preserved via 'part'.

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

// ── Editable text-field semantics ──────────────────────────────────────────

typedef _MoveBy = void Function(bool forward, bool extend);

/// Publishes editable text-field semantics for the hand-painted surface via a
/// `RenderObject` (so it can expose the live `textSelection` and word-
/// granularity cursor actions the `Semantics` widget can't), reusing Flutter's
/// `SemanticsConfiguration`.
class _TextFieldSemantics extends SingleChildRenderObjectWidget {
  const _TextFieldSemantics({
    required this.readOnly,
    required this.value,
    required this.selection,
    required this.onSetSelection,
    required this.onMoveByCharacter,
    required this.onMoveByWord,
    required Widget super.child,
  });

  final bool readOnly;
  final String value;
  final TextSelection? selection;
  final void Function(TextSelection) onSetSelection;
  final _MoveBy onMoveByCharacter;
  final _MoveBy onMoveByWord;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTextFieldSemantics(
        readOnly: readOnly,
        value: value,
        selection: selection,
        onSetSelection: onSetSelection,
        onMoveByCharacter: onMoveByCharacter,
        onMoveByWord: onMoveByWord,
      );

  @override
  void updateRenderObject(
      BuildContext context, _RenderTextFieldSemantics renderObject) {
    renderObject
      ..readOnly = readOnly
      ..value = value
      ..selection = selection
      ..onSetSelection = onSetSelection
      ..onMoveByCharacter = onMoveByCharacter
      ..onMoveByWord = onMoveByWord;
  }
}

class _RenderTextFieldSemantics extends RenderProxyBox {
  _RenderTextFieldSemantics({
    required bool readOnly,
    required String value,
    required TextSelection? selection,
    required this.onSetSelection,
    required this.onMoveByCharacter,
    required this.onMoveByWord,
  })  : _readOnly = readOnly,
        _value = value,
        _selection = selection;

  bool _readOnly;
  set readOnly(bool v) {
    if (v == _readOnly) return;
    _readOnly = v;
    markNeedsSemanticsUpdate();
  }

  String _value;
  set value(String v) {
    if (v == _value) return;
    _value = v;
    markNeedsSemanticsUpdate();
  }

  TextSelection? _selection;
  set selection(TextSelection? v) {
    if (v == _selection) return;
    _selection = v;
    markNeedsSemanticsUpdate();
  }

  // Callbacks delegate to the (stable) editor state, so swapping them needs no
  // semantics rebuild.
  void Function(TextSelection) onSetSelection;
  _MoveBy onMoveByCharacter;
  _MoveBy onMoveByWord;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isTextField = true
      ..isReadOnly = _readOnly
      ..value = _value
      // A non-empty semantic value requires a direction; derive it (RTL-aware).
      ..textDirection = resolveBaseDirection(_value);
    final sel = _selection;
    if (sel != null) config.textSelection = sel;
    if (!_readOnly) {
      config
        ..onSetSelection = onSetSelection
        ..onMoveCursorForwardByCharacter = ((extend) => onMoveByCharacter(true, extend))
        ..onMoveCursorBackwardByCharacter = ((extend) => onMoveByCharacter(false, extend))
        ..onMoveCursorForwardByWord = ((extend) => onMoveByWord(true, extend))
        ..onMoveCursorBackwardByWord = ((extend) => onMoveByWord(false, extend));
    }
  }
}

// ── Selection bubble toolbar ───────────────────────────────────────────────

/// A compact floating toolbar shown over a text selection (Medium/Google-Docs
/// style) for quick inline formatting.
class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({required this.controller, required this.labels});
  final MarkdownEditorController controller;
  final MarkdownEditorLabels labels;

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
            btn('bold', Icons.format_bold, 'bold', labels.bold),
            btn('italic', Icons.format_italic, 'italic', labels.italic),
            btn('strike', Icons.format_strikethrough, 'strike',
                labels.strikethrough),
            btn('highlight', Icons.highlight, 'highlight', labels.highlight),
            btn('code', Icons.code, 'code', labels.inlineCode),
          ],
        ),
      ),
    );
  }
}

// ── Toolbar ────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.labels});
  final MarkdownEditorController controller;
  final MarkdownEditorLabels labels;

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
                          tooltip: labels.undo,
                          icon: const Icon(Icons.undo),
                          onPressed: controller.canUndo ? controller.undo : null,
                        ),
                        IconButton(
                          key: const Key('markey_redo'),
                          tooltip: labels.redo,
                          icon: const Icon(Icons.redo),
                          onPressed: controller.canRedo ? controller.redo : null,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          key: const Key('markey_bold'),
                          tooltip: labels.bold,
                          icon: const Icon(Icons.format_bold),
                          onPressed: isSource
                              ? null
                              : () => controller.toggleMark('bold'),
                        ),
                        IconButton(
                          key: const Key('markey_italic'),
                          tooltip: labels.italic,
                          icon: const Icon(Icons.format_italic),
                          onPressed: isSource
                              ? null
                              : () => controller.toggleMark('italic'),
                        ),
                        IconButton(
                          key: const Key('markey_h1'),
                          tooltip: labels.heading1,
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
                  tooltip: isSource ? labels.toggleSourceToRich : labels.toggleSourceToMarkdown,
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
