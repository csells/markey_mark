import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  test('insertImage replaces the empty active block with an image', () {
    final c = MarkdownEditorController();
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(id, 0)));
    c.insertImage('http://x/y.png', alt: 'a cat');
    final img = c.document.nodes.first as ImageNode;
    expect(img.url, 'http://x/y.png');
    expect(img.alt, 'a cat');
    expect(c.markdown, contains('![a cat](http://x/y.png)'));
    c.dispose();
  });

  test('insertImage is undoable', () {
    final c = MarkdownEditorController(markdown: 'hi');
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(id, 2)));
    c.insertImage('http://x.png');
    expect(c.document.nodes.any((n) => n is ImageNode), isTrue);
    c.undo();
    expect(c.document.nodes.any((n) => n is ImageNode), isFalse);
    c.dispose();
  });

  test('there is a default slash item for images', () {
    expect(defaultSlashItems.any((i) => i.id == 'image'), isTrue);
  });
}
