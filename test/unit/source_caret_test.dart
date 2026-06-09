import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  group('markdownOffsetForPosition', () {
    test('maps a caret inside a heading to the source offset', () {
      final c = MarkdownEditorController(markdown: '# Title\n\nbody');
      final id = c.document.nodes.first.id;
      // caret after "Ti" in "# Title" → "# Ti" = offset 4
      final off = c.markdownOffsetForPosition(DocumentPosition.text(id, 2));
      expect(off, 4);
      c.dispose();
    });

    test('maps a caret in a later block past the separators', () {
      final c = MarkdownEditorController(markdown: '# Title\n\nbody');
      final body = c.document.nodes.last.id;
      // "# Title" (7) + "\n\n" (2) + "bo" (2) = 11
      final off = c.markdownOffsetForPosition(DocumentPosition.text(body, 2));
      expect(off, 11);
      c.dispose();
    });
  });

  group('positionForMarkdownOffset', () {
    test('maps a source offset back to the right block and caret', () {
      final c = MarkdownEditorController(markdown: '# Title\n\nbody');
      final body = c.document.nodes.last.id;
      final pos = c.positionForMarkdownOffset(11)!; // into "bo|dy"
      expect(pos.nodeId, body);
      expect((pos.nodePosition as TextNodePosition).offset, 2);
      c.dispose();
    });

    test('round-trips a caret position through the source offset', () {
      final c = MarkdownEditorController(markdown: '## A heading\n\nsome text');
      final body = c.document.nodes.last.id;
      const original = 5; // "some |text"
      final off =
          c.markdownOffsetForPosition(DocumentPosition.text(body, original));
      final back = c.positionForMarkdownOffset(off)!;
      expect(back.nodeId, body);
      expect((back.nodePosition as TextNodePosition).offset, original);
      c.dispose();
    });
  });
}
