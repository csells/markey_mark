import 'package:characters/characters.dart';

import '../model/document.dart';
import '../model/node.dart';
import '../model/position.dart';
import '../model/selection.dart';
import 'operations.dart';
import 'transaction.dart';

/// Resolved context for a selection that lies within a single text block.
class _BlockSel {
  _BlockSel(this.index, this.node, this.start, this.end);
  final int index;
  final TextBlockNode node;
  final int start; // normalized (start <= end), plain-text offsets
  final int end;
  bool get isCollapsed => start == end;
}

/// Pure functions that build [EditTransaction]s for editing intents. They never
/// mutate state; the [Editor] applies what they return. All return `null` when
/// the intent doesn't apply to the current selection.
abstract final class EditCommands {
  /// Resolves a single-block text selection, or null if the selection is
  /// absent, spans multiple blocks, or isn't a text block.
  static _BlockSel? _single(Document doc, DocumentSelection? sel) {
    if (sel == null) return null;
    if (sel.base.nodeId != sel.extent.nodeId) return null;
    final node = doc.nodeById(sel.base.nodeId);
    if (node is! TextBlockNode) return null;
    final basePos = sel.base.nodePosition;
    final extPos = sel.extent.nodePosition;
    if (basePos is! TextNodePosition || extPos is! TextNodePosition) return null;
    final a = basePos.offset;
    final b = extPos.offset;
    final start = a <= b ? a : b;
    final end = a <= b ? b : a;
    final index = doc.indexOfId(node.id);
    return _BlockSel(index, node, start, end);
  }

  static DocumentSelection _caret(String nodeId, int offset) =>
      DocumentSelection.collapsed(DocumentPosition.text(nodeId, offset));

  /// Inserts [text] at the caret, replacing any selected range. Tagged
  /// `'typing'` so rapid insertions coalesce into one undo unit.
  static EditTransaction? insertText(
    Document doc,
    DocumentSelection? sel,
    String text,
  ) {
    final s = _single(doc, sel);
    if (s == null || text.isEmpty) return null;
    final attrs = s.start > 0
        ? s.node.delta.attributesAt(s.start)
        : const <String, Object?>{};
    final newDelta =
        s.node.delta.delete(s.start, s.end).insert(s.start, text, attrs);
    final newNode = s.node.copyWithDelta(newDelta);
    return EditTransaction(
      operations: [ReplaceNodeOp(s.index, s.node, newNode)],
      selectionBefore: sel,
      selectionAfter: _caret(s.node.id, s.start + text.length),
      tag: 'typing',
    );
  }

  /// Deletes the selected range, or one grapheme before the caret. At the start
  /// of a block, merges with the previous text block.
  static EditTransaction? deleteBackward(Document doc, DocumentSelection? sel) {
    final s = _single(doc, sel);
    if (s == null) return null;

    if (!s.isCollapsed) {
      final newNode = s.node.copyWithDelta(s.node.delta.delete(s.start, s.end));
      return EditTransaction(
        operations: [ReplaceNodeOp(s.index, s.node, newNode)],
        selectionBefore: sel,
        selectionAfter: _caret(s.node.id, s.start),
        tag: 'typing',
      );
    }

    if (s.start > 0) {
      final plain = s.node.delta.toPlainText();
      final prevBoundary =
          plain.substring(0, s.start).characters.skipLast(1).string.length;
      final newNode =
          s.node.copyWithDelta(s.node.delta.delete(prevBoundary, s.start));
      return EditTransaction(
        operations: [ReplaceNodeOp(s.index, s.node, newNode)],
        selectionBefore: sel,
        selectionAfter: _caret(s.node.id, prevBoundary),
        tag: 'typing',
      );
    }

    // At offset 0: merge with the previous text block.
    final prev = doc.nodeBefore(s.node.id);
    if (prev is! TextBlockNode) return null;
    final prevIndex = doc.indexOfId(prev.id);
    final joinAt = prev.delta.length;
    final merged = prev.copyWithDelta(prev.delta.concat(s.node.delta));
    return EditTransaction(
      operations: [
        ReplaceNodeOp(prevIndex, prev, merged),
        DeleteNodeOp(s.index, s.node),
      ],
      selectionBefore: sel,
      selectionAfter: _caret(prev.id, joinAt),
      tag: 'merge',
    );
  }

  /// Splits the current block at the caret. The trailing part becomes a new
  /// paragraph (so Enter after a heading drops you into body text).
  static EditTransaction? splitBlock(Document doc, DocumentSelection? sel) {
    final s = _single(doc, sel);
    if (s == null) return null;
    final left = s.node.copyWithDelta(s.node.delta.slice(0, s.start));
    final rightDelta = s.node.delta.slice(s.end, s.node.delta.length);
    final right = TextBlockNode.paragraph(delta: rightDelta);
    return EditTransaction(
      operations: [
        ReplaceNodeOp(s.index, s.node, left),
        InsertNodeOp(s.index + 1, right),
      ],
      selectionBefore: sel,
      selectionAfter: _caret(right.id, 0),
      tag: 'split',
    );
  }

  /// Toggles an inline mark ([key]) over the selected range. No-op when the
  /// selection is collapsed.
  static EditTransaction? toggleMark(
    Document doc,
    DocumentSelection? sel,
    String key,
  ) {
    final s = _single(doc, sel);
    if (s == null || s.isCollapsed) return null;
    final on = !s.node.delta.isFormatted(s.start, s.end, key);
    final newDelta = s.node.delta.format(s.start, s.end, {key: on ? true : null});
    final newNode = s.node.copyWithDelta(newDelta);
    return EditTransaction(
      operations: [ReplaceNodeOp(s.index, s.node, newNode)],
      selectionBefore: sel,
      selectionAfter: sel,
      tag: 'format',
    );
  }

  /// Toggles a task list item's checked state (addressed by node id, since the
  /// tap target is the checkbox, not the caret).
  static EditTransaction? toggleTodo(
    Document doc,
    String nodeId,
    DocumentSelection? sel,
  ) {
    final node = doc.nodeById(nodeId);
    if (node is! TextBlockNode || node.type != BlockType.todoListItem) {
      return null;
    }
    final index = doc.indexOfId(nodeId);
    final newNode = TextBlockNode.todo(
      id: node.id,
      checked: !(node.checked ?? false),
      delta: node.delta,
    );
    return EditTransaction(
      operations: [ReplaceNodeOp(index, node, newNode)],
      selectionBefore: sel,
      selectionAfter: sel,
      tag: 'toggle-todo',
    );
  }

  /// Changes the current block's type (e.g. paragraph → heading).
  static EditTransaction? setBlockType(
    Document doc,
    DocumentSelection? sel,
    String type, {
    int? level,
  }) {
    final s = _single(doc, sel);
    if (s == null) return null;
    if (s.node.type == type && s.node.level == level) return null;
    final newNode = s.node.asType(type, level: level);
    return EditTransaction(
      operations: [ReplaceNodeOp(s.index, s.node, newNode)],
      selectionBefore: sel,
      selectionAfter: sel,
      tag: 'block-type',
    );
  }
}
