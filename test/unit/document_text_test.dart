import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// The unified document text stream (§13): the whole document projects to one
/// flat string, and every position maps bidirectionally to/from a global offset.
void main() {
  TextBlockNode p(String id, String text) =>
      TextBlockNode.paragraph(id: id, delta: Delta.text(text));

  group('DocumentText flattening', () {
    test('joins text blocks with a single separator', () {
      final dt = DocumentText.of(Document([p('a', 'a'), p('b', 'bb'), p('c', 'ccc')]));
      expect(dt.text, 'a\nbb\nccc');
    });

    test('skips non-text (atomic) blocks but keeps surrounding order', () {
      final dt = DocumentText.of(Document([p('a', 'x'), HorizontalRuleNode(id: 'hr'), p('b', 'y')]));
      expect(dt.text, 'x\ny');
      expect(dt.covers('hr'), isFalse);
      expect(dt.covers('a'), isTrue);
    });
  });

  group('offset ⇄ position mapping', () {
    final doc = Document([p('a', 'a'), p('b', 'bb'), p('c', 'ccc')]);
    final dt = DocumentText.of(doc);

    test('offsetOf maps a block-local position to a global offset', () {
      expect(dt.offsetOf(DocumentPosition.text('a', 0)), 0);
      expect(dt.offsetOf(DocumentPosition.text('a', 1)), 1);
      expect(dt.offsetOf(DocumentPosition.text('b', 0)), 2);
      expect(dt.offsetOf(DocumentPosition.text('b', 2)), 4);
      expect(dt.offsetOf(DocumentPosition.text('c', 0)), 5);
      expect(dt.offsetOf(DocumentPosition.text('c', 3)), 8);
    });

    test('positionAt maps a global offset back to a position', () {
      expect(dt.positionAt(0), DocumentPosition.text('a', 0));
      expect(dt.positionAt(4), DocumentPosition.text('b', 2)); // end of "bb"
      expect(dt.positionAt(5), DocumentPosition.text('c', 0)); // start of "ccc"
      expect(dt.positionAt(8), DocumentPosition.text('c', 3));
    });

    test('round-trips for every offset in the stream', () {
      for (var g = 0; g <= dt.text.length; g++) {
        expect(dt.offsetOf(dt.positionAt(g)), g, reason: 'g=$g');
      }
    });
  });

  group('selection ⇄ range', () {
    final doc = Document([p('a', 'hello'), p('b', 'world')]);
    final dt = DocumentText.of(doc);

    test('a cross-block selection is one contiguous stream range', () {
      final sel = DocumentSelection(
        base: DocumentPosition.text('a', 2),
        extent: DocumentPosition.text('b', 3),
      );
      expect(dt.rangeOf(sel), (2, 9)); // "llo\nwor"
    });

    test('selectionOf is the inverse of rangeOf', () {
      final sel = dt.selectionOf(2, 9);
      expect(sel.base, DocumentPosition.text('a', 2));
      expect(sel.extent, DocumentPosition.text('b', 3));
    });
  });
}
