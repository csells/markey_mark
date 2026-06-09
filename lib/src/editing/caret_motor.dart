import 'package:characters/characters.dart';

import '../model/document.dart';
import '../model/node.dart';
import '../model/position.dart';

/// The granularity of a caret/selection movement, mirroring Flutter's
/// `MovementModifier` (super_editor) and the `DirectionalCaretMovementIntent`
/// family (flutter framework).
enum CaretGranularity {
  /// One grapheme cluster.
  character,

  /// To the next/previous word boundary.
  word,

  /// To the start/end of the current logical line (the block for a paragraph;
  /// the physical line for a code block; the cell text for a table cell).
  lineBoundary,

  /// To the start/end of the document (first/last editable block).
  documentBoundary,
}

/// A pure, **layout-independent** caret/selection motor.
///
/// It answers "what is the caret position one [CaretGranularity] step in a
/// direction from here?" for the whole document, crossing block boundaries and
/// working uniformly across paragraphs, code blocks, and table cells. This is
/// the logic Flutter's `RenderEditable`/`TextLayoutMetrics` provide for a single
/// field, generalized to our multi-block model the way super_editor's
/// `CommonEditorOperations` orchestrates per-component movement.
///
/// Vertical (line up/down) movement is inherently visual — it needs the painted
/// geometry to preserve a goal column — so it lives at the widget layer. Every
/// horizontal / word / line-boundary / document-boundary movement, plus the
/// double/triple-click selection ranges, is computed here with no widget
/// dependency, so it is exhaustively unit-testable.
class CaretMotor {
  const CaretMotor(this.document);

  final Document document;

  /// The next caret position one [granularity] step from [from] in the given
  /// direction, or null when there is nowhere to go (document edge, or the move
  /// would leave a table cell).
  DocumentPosition? move(
    DocumentPosition from, {
    required bool forward,
    required CaretGranularity granularity,
  }) {
    final node = document.nodeById(from.nodeId);
    if (node == null) return null;
    final np = from.nodePosition;

    // Table cells are self-contained sub-editors: movement stays within the
    // cell (crossing cells is a separate, Tab-driven concern).
    if (node is TableNode && np is TableCellPosition) {
      final text = node.cellText(np.row, np.col);
      final next = _withinText(text, np.offset, forward, granularity);
      if (next == null) return null;
      return DocumentPosition(
          nodeId: node.id, nodePosition: np.copyWith(offset: next));
    }

    if (np is! TextNodePosition) return null;
    final text = _textOf(node);
    if (text == null) return null;
    final offset = np.offset.clamp(0, text.length);

    switch (granularity) {
      case CaretGranularity.documentBoundary:
        return forward ? _documentEnd() : _documentStart();
      case CaretGranularity.lineBoundary:
        final (start, end) = _lineBoundsAt(text, offset);
        return DocumentPosition.text(node.id, forward ? end : start);
      case CaretGranularity.character:
      case CaretGranularity.word:
        final within = _withinText(text, offset, forward, granularity);
        if (within != null) return DocumentPosition.text(node.id, within);
        // At the block edge in this direction — cross to the neighbour.
        final neighbour =
            forward ? _nextEditable(node.id) : _prevEditable(node.id);
        if (neighbour == null) return null;
        final nt = _textOf(neighbour)!;
        return DocumentPosition.text(neighbour.id, forward ? 0 : nt.length);
    }
  }

  /// The word range around [pos] (double-click selection), or null if [pos]
  /// isn't on a text-bearing block.
  (DocumentPosition, DocumentPosition)? wordRangeAt(DocumentPosition pos) {
    final text = _textOfId(pos.nodeId);
    if (text == null) return null;
    final np = pos.nodePosition;
    final o = (np is TextNodePosition ? np.offset : 0).clamp(0, text.length);
    final (start, end) = _wordBoundsAt(text, o);
    return (
      DocumentPosition.text(pos.nodeId, start),
      DocumentPosition.text(pos.nodeId, end),
    );
  }

  /// The logical-line range around [pos] (triple-click selection).
  (DocumentPosition, DocumentPosition)? lineRangeAt(DocumentPosition pos) {
    final text = _textOfId(pos.nodeId);
    if (text == null) return null;
    final np = pos.nodePosition;
    final o = (np is TextNodePosition ? np.offset : 0).clamp(0, text.length);
    final (start, end) = _lineBoundsAt(text, o);
    return (
      DocumentPosition.text(pos.nodeId, start),
      DocumentPosition.text(pos.nodeId, end),
    );
  }

  // ── Within-text movement (returns null at the edge in the move direction) ──

  int? _withinText(
      String text, int offset, bool forward, CaretGranularity granularity) {
    switch (granularity) {
      case CaretGranularity.character:
        if (forward) {
          return offset >= text.length ? null : _nextGrapheme(text, offset);
        }
        return offset <= 0 ? null : _prevGrapheme(text, offset);
      case CaretGranularity.word:
        if (forward) {
          return offset >= text.length ? null : _wordRight(text, offset);
        }
        return offset <= 0 ? null : _wordLeft(text, offset);
      case CaretGranularity.lineBoundary:
        final (start, end) = _lineBoundsAt(text, offset);
        final target = forward ? end : start;
        return target == offset ? null : target;
      case CaretGranularity.documentBoundary:
        final target = forward ? text.length : 0;
        return target == offset ? null : target;
    }
  }

  // ── Text accessors ─────────────────────────────────────────────────────

  static bool _isEditable(Node n) => n is TextBlockNode || n is CodeBlockNode;

  static String? _textOf(Node node) {
    if (node is TextBlockNode) return node.delta.toPlainText();
    if (node is CodeBlockNode) return node.code;
    return null;
  }

  String? _textOfId(String id) {
    final n = document.nodeById(id);
    return n == null ? null : _textOf(n);
  }

  Node? _nextEditable(String id) {
    final i = document.indexOfId(id);
    if (i < 0) return null;
    for (var j = i + 1; j < document.length; j++) {
      final n = document.nodeAt(j);
      if (_isEditable(n)) return n;
    }
    return null;
  }

  Node? _prevEditable(String id) {
    final i = document.indexOfId(id);
    if (i < 0) return null;
    for (var j = i - 1; j >= 0; j--) {
      final n = document.nodeAt(j);
      if (_isEditable(n)) return n;
    }
    return null;
  }

  DocumentPosition? _documentStart() {
    for (var i = 0; i < document.length; i++) {
      final n = document.nodeAt(i);
      if (_isEditable(n)) return DocumentPosition.text(n.id, 0);
    }
    return null;
  }

  DocumentPosition? _documentEnd() {
    for (var i = document.length - 1; i >= 0; i--) {
      final n = document.nodeAt(i);
      if (_isEditable(n)) {
        return DocumentPosition.text(n.id, _textOf(n)!.length);
      }
    }
    return null;
  }

  // ── Grapheme boundaries (cluster-aware, like Flutter's CharacterBoundary) ──

  static int _nextGrapheme(String text, int offset) {
    if (offset >= text.length) return text.length;
    var pos = 0;
    for (final cluster in text.characters) {
      pos += cluster.length;
      if (pos > offset) return pos;
    }
    return text.length;
  }

  static int _prevGrapheme(String text, int offset) {
    if (offset <= 0) return 0;
    var pos = 0;
    for (final cluster in text.characters) {
      final next = pos + cluster.length;
      if (next >= offset) return pos;
      pos = next;
    }
    return pos;
  }

  // ── Word boundaries (editor semantics: skip whitespace, then a run of one
  //    class — word chars or punctuation — matching Flutter's word-wise move). ──

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d || c == 0x0c || c == 0x0b;

  static bool _isWordChar(int c) =>
      c == 0x5f || // _
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5a) || // A-Z
      (c >= 0x61 && c <= 0x7a) || // a-z
      c > 0x7f; // treat non-ASCII as word chars (letters/CJK/etc.)

  static int _wordRight(String text, int offset) {
    var i = offset;
    final n = text.length;
    while (i < n && _isSpace(text.codeUnitAt(i))) {
      i++;
    }
    if (i < n) {
      if (_isWordChar(text.codeUnitAt(i))) {
        while (i < n && _isWordChar(text.codeUnitAt(i))) {
          i++;
        }
      } else {
        while (i < n &&
            !_isSpace(text.codeUnitAt(i)) &&
            !_isWordChar(text.codeUnitAt(i))) {
          i++;
        }
      }
    }
    return i;
  }

  static int _wordLeft(String text, int offset) {
    var i = offset;
    while (i > 0 && _isSpace(text.codeUnitAt(i - 1))) {
      i--;
    }
    if (i > 0) {
      if (_isWordChar(text.codeUnitAt(i - 1))) {
        while (i > 0 && _isWordChar(text.codeUnitAt(i - 1))) {
          i--;
        }
      } else {
        while (i > 0 &&
            !_isSpace(text.codeUnitAt(i - 1)) &&
            !_isWordChar(text.codeUnitAt(i - 1))) {
          i--;
        }
      }
    }
    return i;
  }

  /// The word containing [offset], preferring the character at [offset], then
  /// the one before it (so a click just after a word still selects it).
  static (int, int) _wordBoundsAt(String text, int offset) {
    if (text.isEmpty) return (0, 0);
    var probe = offset;
    if (probe >= text.length) probe = text.length - 1;
    // If sitting on a space and there's a word char just before, probe that.
    if (_isSpace(text.codeUnitAt(probe)) &&
        offset > 0 &&
        !_isSpace(text.codeUnitAt(offset - 1))) {
      probe = offset - 1;
    }
    final onWord = _isWordChar(text.codeUnitAt(probe));
    final onSpace = _isSpace(text.codeUnitAt(probe));
    bool sameClass(int c) =>
        onSpace ? _isSpace(c) : (onWord ? _isWordChar(c) : (!_isSpace(c) && !_isWordChar(c)));
    var start = probe;
    while (start > 0 && sameClass(text.codeUnitAt(start - 1))) {
      start--;
    }
    var end = probe;
    while (end < text.length && sameClass(text.codeUnitAt(end))) {
      end++;
    }
    return (start, end);
  }

  // ── Logical line bounds (between hard '\n's; whole block for a paragraph) ──

  static (int, int) _lineBoundsAt(String text, int offset) {
    var start = offset.clamp(0, text.length);
    while (start > 0 && text.codeUnitAt(start - 1) != 0x0a) {
      start--;
    }
    var end = offset.clamp(0, text.length);
    while (end < text.length && text.codeUnitAt(end) != 0x0a) {
      end++;
    }
    return (start, end);
  }
}
