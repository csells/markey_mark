import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  MarkdownEditorController make() =>
      MarkdownEditorController(markdown: 'one\n\ntwo\n\nthree');

  List<String> order(MarkdownEditorController c) => [
        for (final n in c.document.nodes) (n as TextBlockNode).delta.toPlainText()
      ];

  test('moveBlockDown swaps with the next block', () {
    final c = make();
    c.moveBlockDown(c.document.nodes.first.id);
    expect(order(c), ['two', 'one', 'three']);
    c.dispose();
  });

  test('moveBlockUp swaps with the previous block', () {
    final c = make();
    c.moveBlockUp(c.document.nodes[2].id);
    expect(order(c), ['one', 'three', 'two']);
    c.dispose();
  });

  test('moving is undoable', () {
    final c = make();
    c.moveBlockDown(c.document.nodes.first.id);
    c.undo();
    expect(order(c), ['one', 'two', 'three']);
    c.dispose();
  });

  test('moveBlockUp on the first block is a no-op', () {
    final c = make();
    c.moveBlockUp(c.document.nodes.first.id);
    expect(order(c), ['one', 'two', 'three']);
    c.dispose();
  });

  test('moveBlockDown on the last block is a no-op', () {
    final c = make();
    c.moveBlockDown(c.document.nodes.last.id);
    expect(order(c), ['one', 'two', 'three']);
    c.dispose();
  });
}
