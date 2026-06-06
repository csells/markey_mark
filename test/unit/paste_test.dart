import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  DocumentSelection caret(MarkdownEditorController c, int o) =>
      DocumentSelection.collapsed(
          DocumentPosition.text(c.document.nodes.first.id, o));

  TextBlockNode tb(MarkdownEditorController c, int i) =>
      c.document.nodes[i] as TextBlockNode;

  group('pasteMarkdown', () {
    test('inline paste preserves formatting and merges into the paragraph', () {
      final c = MarkdownEditorController(markdown: 'Hi');
      c.setSelection(caret(c, 2));
      c.pasteMarkdown(' **bold** there');
      expect(tb(c, 0).delta.toPlainText(), 'Hi bold there');
      expect(tb(c, 0).delta.isFormatted(3, 7, 'bold'), isTrue);
      c.dispose();
    });

    test('multi-block paste inserts parsed blocks', () {
      final c = MarkdownEditorController(markdown: 'Start');
      c.setSelection(caret(c, 5));
      c.pasteMarkdown('# Heading\n\n- item one\n- item two');
      final types = c.document.nodes
          .map((n) => (n as TextBlockNode).type)
          .toList();
      expect(types, contains(BlockType.heading));
      expect(types.where((t) => t == BlockType.bulletedListItem).length, 2);
      c.dispose();
    });

    test('paste is undoable', () {
      final c = MarkdownEditorController(markdown: 'X');
      c.setSelection(caret(c, 1));
      c.pasteMarkdown(' more');
      expect(tb(c, 0).delta.toPlainText(), 'X more');
      c.undo();
      expect(tb(c, 0).delta.toPlainText(), 'X');
      c.dispose();
    });

    test('empty paste is a no-op', () {
      final c = MarkdownEditorController(markdown: 'keep');
      c.setSelection(caret(c, 4));
      c.pasteMarkdown('');
      expect(tb(c, 0).delta.toPlainText(), 'keep');
      c.dispose();
    });
  });
}
