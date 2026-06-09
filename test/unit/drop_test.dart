import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  group('applyDrop', () {
    test('dropped text is parsed as Markdown at the caret', () {
      final c = MarkdownEditorController(markdown: 'start');
      final id = c.document.nodes.first.id;
      c.setSelection(
          DocumentSelection.collapsed(DocumentPosition.text(id, 5)));
      c.applyDrop(const [DroppedItem.text('**bold**')]);
      expect(c.document.nodes.first, isA<TextBlockNode>());
      expect((c.document.nodes.first as TextBlockNode)
          .delta
          .isFormatted(5, 9, 'bold'), isTrue);
      c.dispose();
    });

    test('a dropped image becomes an image block', () {
      final c = MarkdownEditorController();
      final id = c.document.nodes.first.id;
      c.setSelection(
          DocumentSelection.collapsed(DocumentPosition.text(id, 0)));
      c.applyDrop(const [DroppedItem.image('pic.png', alt: 'a pic')]);
      final img = c.document.nodes.whereType<ImageNode>().single;
      expect(img.url, 'pic.png');
      expect(img.alt, 'a pic');
      c.dispose();
    });

    test('dropping at an explicit position moves the caret there first', () {
      final c = MarkdownEditorController(markdown: 'one\n\ntwo');
      final second = c.document.nodes[1].id;
      c.applyDrop(
        const [DroppedItem.text(' X')],
        at: DocumentPosition.text(second, 3),
      );
      expect((c.document.nodes[1] as TextBlockNode).delta.toPlainText(), 'two X');
      c.dispose();
    });

    test('multiple dropped items are inserted in order', () {
      final c = MarkdownEditorController();
      final id = c.document.nodes.first.id;
      c.setSelection(
          DocumentSelection.collapsed(DocumentPosition.text(id, 0)));
      c.applyDrop(const [
        DroppedItem.text('hi '),
        DroppedItem.image('a.png'),
      ]);
      expect(c.document.nodes.whereType<ImageNode>().length, 1);
      expect(c.markdown, contains('hi'));
      expect(c.markdown, contains('a.png'));
      c.dispose();
    });
  });
}
