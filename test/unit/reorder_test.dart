import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  group('reorderBlock', () {
    test('moves a block to a later index', () {
      final c = MarkdownEditorController(markdown: 'a\n\nb\n\nc');
      final aId = c.document.nodes.first.id;
      c.reorderBlock(0, 2);
      expect(c.document.nodes.map((n) => (n as TextBlockNode).delta.toPlainText()),
          ['b', 'c', 'a']);
      expect(c.document.nodes.last.id, aId); // identity preserved
      c.dispose();
    });

    test('moves a block to an earlier index', () {
      final c = MarkdownEditorController(markdown: 'a\n\nb\n\nc');
      c.reorderBlock(2, 0);
      expect(c.document.nodes.map((n) => (n as TextBlockNode).delta.toPlainText()),
          ['c', 'a', 'b']);
      c.dispose();
    });

    test('is a single undo unit', () {
      final c = MarkdownEditorController(markdown: 'a\n\nb');
      c.reorderBlock(0, 1);
      expect(c.markdown, 'b\n\na');
      c.undo();
      expect(c.markdown, 'a\n\nb');
      c.dispose();
    });

    test('out-of-range or no-op indices do nothing', () {
      final c = MarkdownEditorController(markdown: 'a\n\nb');
      c.reorderBlock(0, 0);
      c.reorderBlock(5, 0);
      expect(c.markdown, 'a\n\nb');
      c.dispose();
    });
  });
}
