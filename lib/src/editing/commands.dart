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

/// Resolved context for a selection spanning two or more blocks (document
/// order: [startIndex] <= [endIndex]).
class _MultiSel {
  _MultiSel(this.startIndex, this.startNode, this.startOffset, this.endIndex,
      this.endNode, this.endOffset);
  final int startIndex;
  final Node startNode;
  final int startOffset;
  final int endIndex;
  final Node endNode;
  final int endOffset;
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

  /// Resolves a selection confined to a single code block (treated as editable
  /// plain text), or null. (index, node, start, end) with start <= end.
  static (int, CodeBlockNode, int, int)? _singleCode(
      Document doc, DocumentSelection? sel) {
    if (sel == null || sel.base.nodeId != sel.extent.nodeId) return null;
    final node = doc.nodeById(sel.base.nodeId);
    if (node is! CodeBlockNode) return null;
    final basePos = sel.base.nodePosition;
    final extPos = sel.extent.nodePosition;
    if (basePos is! TextNodePosition || extPos is! TextNodePosition) return null;
    final a = basePos.offset, b = extPos.offset;
    return (doc.indexOfId(node.id), node, a <= b ? a : b, a <= b ? b : a);
  }

  static DocumentSelection _caret(String nodeId, int offset) =>
      DocumentSelection.collapsed(DocumentPosition.text(nodeId, offset));

  /// Resolves a selection that spans two or more blocks (in document order),
  /// or null when it is absent or confined to a single block.
  static _MultiSel? _multi(Document doc, DocumentSelection? sel) {
    if (sel == null || sel.base.nodeId == sel.extent.nodeId) return null;
    final iBase = doc.indexOfId(sel.base.nodeId);
    final iExt = doc.indexOfId(sel.extent.nodeId);
    if (iBase < 0 || iExt < 0) return null;
    final (startPos, startIdx, endPos, endIdx) = iBase <= iExt
        ? (sel.base, iBase, sel.extent, iExt)
        : (sel.extent, iExt, sel.base, iBase);
    return _MultiSel(
      startIdx,
      doc.nodes[startIdx],
      _offsetOf(startPos.nodePosition),
      endIdx,
      doc.nodes[endIdx],
      _offsetOf(endPos.nodePosition),
    );
  }

  static int _offsetOf(NodePosition pos) =>
      pos is TextNodePosition ? pos.offset : 0;

  /// Deletes a selection spanning two or more blocks: the tail of the first
  /// block and the head of the last block are removed, every block in between
  /// is dropped, and the two remnants merge into the first block (keeping its
  /// type). Returns null unless both endpoints are text blocks.
  static EditTransaction? deleteSelection(Document doc, DocumentSelection? sel) {
    final m = _multi(doc, sel);
    if (m == null) return null;
    if (m.startNode is! TextBlockNode || m.endNode is! TextBlockNode) return null;
    final first = m.startNode as TextBlockNode;
    final last = m.endNode as TextBlockNode;
    final mergedDelta = first.delta
        .slice(0, m.startOffset)
        .concat(last.delta.slice(m.endOffset, last.delta.length));
    final ops = <Operation>[
      ReplaceNodeOp(m.startIndex, first, first.copyWithDelta(mergedDelta)),
      // Delete trailing blocks high-index-first so indices stay valid.
      for (var idx = m.endIndex; idx > m.startIndex; idx--)
        DeleteNodeOp(idx, doc.nodes[idx]),
    ];
    return EditTransaction(
      operations: ops,
      selectionBefore: sel,
      selectionAfter: _caret(first.id, m.startOffset),
      tag: 'delete-selection',
    );
  }

  /// Inserts [text] at the caret, replacing any selected range. Tagged
  /// `'typing'` so rapid insertions coalesce into one undo unit.
  static EditTransaction? insertText(
    Document doc,
    DocumentSelection? sel,
    String text,
  ) {
    if (text.isEmpty) return null;
    final cb = _singleCode(doc, sel);
    if (cb != null) {
      final (index, node, start, end) = cb;
      final newCode = node.code.replaceRange(start, end, text);
      return EditTransaction(
        operations: [ReplaceNodeOp(index, node, node.copyWithCode(newCode))],
        selectionBefore: sel,
        selectionAfter: _caret(node.id, start + text.length),
        tag: 'typing',
      );
    }
    final s = _single(doc, sel);
    if (s == null) {
      // A cross-block selection: delete it, then insert the text at the join.
      final m = _multi(doc, sel);
      if (m == null) return null;
      if (m.startNode is! TextBlockNode || m.endNode is! TextBlockNode) {
        return null;
      }
      final first = m.startNode as TextBlockNode;
      final last = m.endNode as TextBlockNode;
      final attrs = m.startOffset > 0
          ? first.delta.attributesAt(m.startOffset)
          : const <String, Object?>{};
      final left = first.delta.slice(0, m.startOffset);
      final mergedDelta = left
          .insert(left.length, text, attrs)
          .concat(last.delta.slice(m.endOffset, last.delta.length));
      final ops = <Operation>[
        ReplaceNodeOp(m.startIndex, first, first.copyWithDelta(mergedDelta)),
        for (var idx = m.endIndex; idx > m.startIndex; idx--)
          DeleteNodeOp(idx, doc.nodes[idx]),
      ];
      return EditTransaction(
        operations: ops,
        selectionBefore: sel,
        selectionAfter: _caret(first.id, m.startOffset + text.length),
        tag: 'typing',
      );
    }
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
    final cb = _singleCode(doc, sel);
    if (cb != null) {
      final (index, node, start, end) = cb;
      if (start == end) {
        if (start == 0) return null; // at code start: nothing to delete here
        final newCode = node.code.replaceRange(start - 1, start, '');
        return EditTransaction(
          operations: [ReplaceNodeOp(index, node, node.copyWithCode(newCode))],
          selectionBefore: sel,
          selectionAfter: _caret(node.id, start - 1),
          tag: 'typing',
        );
      }
      final newCode = node.code.replaceRange(start, end, '');
      return EditTransaction(
        operations: [ReplaceNodeOp(index, node, node.copyWithCode(newCode))],
        selectionBefore: sel,
        selectionAfter: _caret(node.id, start),
        tag: 'typing',
      );
    }

    // A cross-block selection collapses to a single delete-and-merge.
    final crossBlock = deleteSelection(doc, sel);
    if (crossBlock != null) return crossBlock;

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
    // Enter inside a code block inserts a literal newline; it never splits.
    final cb = _singleCode(doc, sel);
    if (cb != null) {
      final (index, node, start, end) = cb;
      final newCode = node.code.replaceRange(start, end, '\n');
      return EditTransaction(
        operations: [ReplaceNodeOp(index, node, node.copyWithCode(newCode))],
        selectionBefore: sel,
        selectionAfter: _caret(node.id, start + 1),
        tag: 'typing',
      );
    }
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
    if (s != null) {
      if (s.isCollapsed) return null;
      final on = !s.node.delta.isFormatted(s.start, s.end, key);
      final newDelta =
          s.node.delta.format(s.start, s.end, {key: on ? true : null});
      final newNode = s.node.copyWithDelta(newDelta);
      return EditTransaction(
        operations: [ReplaceNodeOp(s.index, s.node, newNode)],
        selectionBefore: sel,
        selectionAfter: sel,
        tag: 'format',
      );
    }

    // Cross-block: format each spanned text block's portion.
    final m = _multi(doc, sel);
    if (m == null) return null;
    final portions = <(int, TextBlockNode, int, int)>[];
    for (var idx = m.startIndex; idx <= m.endIndex; idx++) {
      final node = doc.nodes[idx];
      if (node is! TextBlockNode) continue;
      final from = idx == m.startIndex ? m.startOffset : 0;
      final to = idx == m.endIndex ? m.endOffset : node.delta.length;
      if (to > from) portions.add((idx, node, from, to));
    }
    if (portions.isEmpty) return null;
    // Turn the mark on unless every portion already has it (then turn off).
    final allOn =
        portions.every((part) => part.$2.delta.isFormatted(part.$3, part.$4, key));
    final value = allOn ? null : true;
    final ops = <Operation>[
      for (final (idx, node, from, to) in portions)
        ReplaceNodeOp(
            idx, node, node.copyWithDelta(node.delta.format(from, to, {key: value}))),
    ];
    return EditTransaction(
      operations: ops,
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
