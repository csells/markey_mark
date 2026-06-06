import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/node.dart';
import '../model/position.dart';
import '../model/selection.dart';
import '../render/delta_text.dart';
import '../theme/editor_style.dart';
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
  });

  final MarkdownEditorController controller;
  final EditorStyle? style;
  final bool showToolbar;
  final bool readOnly;
  final FocusNode? focusNode;

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> with TextInputClient {
  late FocusNode _focusNode;
  final TextEditingController _sourceController = TextEditingController();
  final ValueNotifier<bool> _caretBlink = ValueNotifier<bool>(true);
  Timer? _blinkTimer;

  TextInputConnection? _connection;
  TextEditingValue _imeValue = TextEditingValue.empty;

  MarkdownEditorController get _c => widget.controller;

  EditorStyle _resolveStyle() =>
      widget.style ?? EditorStyle.fromTheme(Theme.of(context));

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _c.addListener(_onControllerChanged);
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 530), (_) {
      _caretBlink.value = !_caretBlink.value;
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _caretBlink.dispose();
    _c.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) _focusNode.dispose();
    _sourceController.dispose();
    _connection?.close();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(_syncImeFromModel);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _openConnection();
    } else {
      _closeConnection();
    }
    if (mounted) setState(() {});
  }

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
    final tp = _painterFor(node, width);
    final pos = tp.getPositionForOffset(localPos);
    _focusNode.requestFocus();
    _c.setSelection(DocumentSelection.collapsed(
      DocumentPosition.text(node.id, pos.offset),
    ));
  }

  void _extendSelection(TextBlockNode node, Offset localPos, double width) {
    if (widget.readOnly) return;
    final tp = _painterFor(node, width);
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

  TextPainter _painterFor(TextBlockNode node, double width) {
    final style = _resolveStyle();
    final span = deltaToTextSpan(node.delta, baseStyleFor(node, style), style);
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout(maxWidth: width);
    return tp;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final body = _c.mode == EditorMode.source ? _buildSource() : _buildWysiwyg();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showToolbar) _Toolbar(controller: _c),
        Expanded(child: body),
      ],
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
    return Shortcuts(
      shortcuts: _shortcuts(),
      child: Actions(
        actions: _actions(),
        child: Focus(
          focusNode: _focusNode,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _focusNode.requestFocus,
            child: ListView.separated(
              padding: style.padding,
              itemCount: _c.document.nodes.length,
              separatorBuilder: (_, __) => SizedBox(height: style.blockSpacing),
              itemBuilder: (context, index) {
                final node = _c.document.nodes[index];
                if (node is! TextBlockNode) {
                  return const SizedBox.shrink();
                }
                return _buildBlock(node, style);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(TextBlockNode node, EditorStyle style) {
    final base = baseStyleFor(node, style);
    final span = deltaToTextSpan(node.delta, base, style);
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
        final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
          ..layout(maxWidth: width);
        final height = math.max(tp.height, base.fontSize ?? 16);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _placeCaret(node, d.localPosition, width),
          onPanStart: (d) => _placeCaret(node, d.localPosition, width),
          onPanUpdate: (d) => _extendSelection(node, d.localPosition, width),
          child: CustomPaint(
            size: Size(width, height),
            painter: _BlockPainter(
              span: span,
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
      const SingleActivator(LogicalKeyboardKey.arrowLeft):
          const _MoveCaretIntent(false),
      const SingleActivator(LogicalKeyboardKey.arrowRight):
          const _MoveCaretIntent(true),
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

class _MoveCaretIntent extends Intent {
  const _MoveCaretIntent(this.forward);
  final bool forward;
}

// ── Painter ────────────────────────────────────────────────────────────────

class _BlockPainter extends CustomPainter {
  _BlockPainter({
    required this.span,
    required this.selection,
    required this.caretOffset,
    required this.showCaret,
    required this.caretBlink,
    required this.selectionColor,
    required this.caretColor,
  }) : super(repaint: caretBlink);

  final InlineSpan span;
  final TextSelection? selection;
  final int? caretOffset;
  final bool showCaret;
  final ValueListenable<bool> caretBlink;
  final Color selectionColor;
  final Color caretColor;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout(maxWidth: size.width);

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
      old.span != span ||
      old.selection != selection ||
      old.caretOffset != caretOffset ||
      old.showCaret != showCaret ||
      old.selectionColor != selectionColor ||
      old.caretColor != caretColor;
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
                  onPressed: isSource ? null : () => controller.toggleMark('bold'),
                ),
                IconButton(
                  key: const Key('markey_italic'),
                  tooltip: 'Italic',
                  icon: const Icon(Icons.format_italic),
                  onPressed:
                      isSource ? null : () => controller.toggleMark('italic'),
                ),
                IconButton(
                  key: const Key('markey_h1'),
                  tooltip: 'Heading 1',
                  icon: const Icon(Icons.title),
                  onPressed: isSource
                      ? null
                      : () => controller.setBlockType(BlockType.heading, level: 1),
                ),
                const Spacer(),
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
