import 'document.dart';
import 'node.dart';
import 'position.dart';
import 'selection.dart';

/// One text-bearing region's span in the flattened [DocumentText.text].
class _Segment {
  const _Segment(this.nodeId, this.start, this.length);
  final String nodeId;
  final int start;
  final int length;
  int get end => start + length;
}

/// The unified document text stream (§13 — "one editor, not four").
///
/// Projects the whole document to a single flat string — the visible plain text
/// of every text-bearing block joined by one separator — and maps
/// bidirectionally between a **global offset** in that string and a
/// `DocumentPosition(nodeId, localOffset)`. This is the seam that lets the IME,
/// selection, and clipboard speak one coordinate system across all blocks,
/// instead of one editor per block.
///
/// v1 covers [TextBlockNode]s (paragraphs, headings, lists, quotes, …); atomic
/// blocks are skipped (not yet traversable in the stream). Code blocks and table
/// cells join the stream in later migration steps.
class DocumentText {
  DocumentText._(this.text, this._segments, this._byId);

  /// Total characters flattened across all [DocumentText.of] calls — a
  /// test/CI hook to prove the IME hot path is *windowed* (a keystroke flattens
  /// only the selection's block(s), not the whole document).
  static int debugFlattenedChars = 0;

  factory DocumentText.of(Document doc) {
    final segs = <_Segment>[];
    final byId = <String, _Segment>{};
    final buf = StringBuffer();
    var cursor = 0;
    for (final node in doc.nodes) {
      final t = _editableTextOf(node);
      if (t == null) continue;
      if (segs.isNotEmpty) {
        buf.write('\n');
        cursor += 1;
      }
      final seg = _Segment(node.id, cursor, t.length);
      buf.write(t);
      cursor += t.length;
      segs.add(seg);
      byId[node.id] = seg;
    }
    final text = buf.toString();
    debugFlattenedChars += text.length;
    return DocumentText._(text, segs, byId);
  }

  /// The editable plain text a node contributes to the stream, or null if it
  /// isn't a text-bearing/editable block.
  static String? _editableTextOf(Node node) {
    if (node is TextBlockNode) return node.delta.toPlainText();
    if (node is CodeBlockNode) return node.code;
    return null;
  }

  /// The flattened visible text of all text-bearing blocks.
  final String text;
  final List<_Segment> _segments;
  final Map<String, _Segment> _byId;

  /// Whether [nodeId] contributes a span to the stream.
  bool covers(String nodeId) => _byId.containsKey(nodeId);

  /// Whether any block contributes text (false for an all-atomic document).
  bool get coversAny => _segments.isNotEmpty;

  /// The global offset of a block-local [position]. Throws if its node isn't in
  /// the stream.
  int offsetOf(DocumentPosition position) {
    final seg = _byId[position.nodeId];
    if (seg == null) {
      throw ArgumentError('node ${position.nodeId} is not in the text stream');
    }
    final np = position.nodePosition;
    final local = np is TextNodePosition ? np.offset : 0;
    return seg.start + local.clamp(0, seg.length);
  }

  /// The block-local position for a global [offset] (clamped to the stream).
  DocumentPosition positionAt(int offset) {
    if (_segments.isEmpty) {
      throw StateError('empty text stream has no positions');
    }
    final g = offset.clamp(0, text.length);
    // Last segment whose start is <= g (binary search).
    var lo = 0, hi = _segments.length - 1, idx = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_segments[mid].start <= g) {
        idx = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final seg = _segments[idx];
    return DocumentPosition.text(seg.nodeId, (g - seg.start).clamp(0, seg.length));
  }

  /// The selection as a normalized `[start, end)` stream range.
  (int, int) rangeOf(DocumentSelection selection) {
    final a = offsetOf(selection.base);
    final b = offsetOf(selection.extent);
    return a <= b ? (a, b) : (b, a);
  }

  /// Builds a selection from two global offsets (base, extent).
  DocumentSelection selectionOf(int base, int extent) => DocumentSelection(
        base: positionAt(base),
        extent: positionAt(extent),
      );
}
