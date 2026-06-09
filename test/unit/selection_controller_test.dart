import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Step 3: one selection authority. All selection changes go through the
/// controller, expressed in document-stream offsets (DocumentText), so gestures,
/// IME, and keyboard share a single coordinate system.
void main() {
  test('selectByOffsets builds a (cross-block) selection from stream offsets',
      () {
    final c = MarkdownEditorController(markdown: 'hello\n\nworld');
    c.selectByOffsets(2, 9); // "llo\nwor"
    final sel = c.selection!;
    expect(sel.base.nodeId, c.document.nodes.first.id);
    expect((sel.base.nodePosition as TextNodePosition).offset, 2);
    expect(sel.extent.nodeId, c.document.nodes.last.id);
    expect((sel.extent.nodePosition as TextNodePosition).offset, 3);
    c.dispose();
  });

  test('selectionOffsets is the inverse of selectByOffsets', () {
    final c = MarkdownEditorController(markdown: 'hello\n\nworld');
    c.selectByOffsets(2, 9);
    expect(c.selectionOffsets(), (2, 9));
    c.dispose();
  });

  test('placeCaretAt collapses the selection at a position', () {
    final c = MarkdownEditorController(markdown: 'abc');
    final id = c.document.nodes.first.id;
    c.placeCaretAt(DocumentPosition.text(id, 2));
    expect(c.selection!.isCollapsed, isTrue);
    expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 2);
    c.dispose();
  });

  test('extendSelectionTo keeps the anchor and moves only the extent', () {
    final c = MarkdownEditorController(markdown: 'hello\n\nworld');
    final first = c.document.nodes.first.id;
    final last = c.document.nodes.last.id;
    c.placeCaretAt(DocumentPosition.text(first, 1));
    c.extendSelectionTo(DocumentPosition.text(last, 4));
    final sel = c.selection!;
    expect(sel.base.nodeId, first);
    expect((sel.base.nodePosition as TextNodePosition).offset, 1);
    expect(sel.extent.nodeId, last);
    expect((sel.extent.nodePosition as TextNodePosition).offset, 4);
    c.dispose();
  });
}
