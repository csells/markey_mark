import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Convergent collaboration: two peers that edit *concurrently* (while delivery
/// is buffered) must converge to the same document once the buffered ops are
/// flushed — operational transformation rebases each peer's edit against the
/// other's. This is the runtime wiring of the OT layer into `applyRemote`,
/// where the raw (non-transforming) path would diverge.
void main() {
  String text(MarkdownEditorController c) =>
      (c.document.nodes.first as TextBlockNode).delta.toPlainText();

  DocumentSelection caretAt(MarkdownEditorController c, int o) =>
      DocumentSelection.collapsed(DocumentPosition.text(c.document.nodes.first.id, o));

  test('concurrent INSERTIONS in the same block both survive (char-level merge)',
      () {
    final a = MarkdownEditorController(markdown: 'hello');
    final b = MarkdownEditorController(markdown: 'hello');
    final session = OtCollaborationSession([a, b]);

    // Both edit the same block based on the same state, before either is
    // delivered (a network partition).
    a.setSelection(caretAt(a, 0));
    a.insertText('A'); // -> "Ahello" locally
    b.setSelection(caretAt(b, 5));
    b.insertText('B'); // -> "helloB" locally

    // Still diverged (buffered).
    expect(text(a), 'Ahello');
    expect(text(b), 'helloB');

    session.flush();

    // Character-level merge: both insertions land, and the peers converge.
    expect(text(a), text(b));
    expect(text(a), 'AhelloB');

    session.dispose();
    a.dispose();
    b.dispose();
  });

  test('same-block delete vs insert merges and converges (Delta OT)', () {
    final a = MarkdownEditorController(markdown: 'hello');
    final b = MarkdownEditorController(markdown: 'hello');
    final session = OtCollaborationSession([a, b]);
    a.setSelection(caretAt(a, 5));
    a.insertText('!'); // "hello!"
    b.setSelection(DocumentSelection(
      base: DocumentPosition.text(b.document.nodes.first.id, 0),
      extent: DocumentPosition.text(b.document.nodes.first.id, 5),
    ));
    b.deleteBackward(); // delete "hello" -> ""
    session.flush();
    // Both intents preserved: the deletion of "hello" and the inserted "!".
    expect(text(a), text(b));
    expect(text(a), '!');
    session.dispose();
    a.dispose();
    b.dispose();
  });

  test('concurrent edits to different blocks converge', () {
    final a = MarkdownEditorController(markdown: 'one\n\ntwo');
    final b = MarkdownEditorController(markdown: 'one\n\ntwo');
    final session = OtCollaborationSession([a, b]);

    a.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(a.document.nodes[0].id, 3)));
    a.insertText('!');
    b.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(b.document.nodes[1].id, 3)));
    b.insertText('?');

    session.flush();
    expect(a.markdown, b.markdown);
    expect(a.markdown, 'one!\n\ntwo?');

    session.dispose();
    a.dispose();
    b.dispose();
  });

  test('concurrent structural + text edits converge (block insert vs edit)', () {
    final a = MarkdownEditorController(markdown: 'p0\n\np1');
    final b = MarkdownEditorController(markdown: 'p0\n\np1');
    final session = OtCollaborationSession([a, b]);

    // a edits the second block; b splits the first block (a structural insert).
    a.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(a.document.nodes[1].id, 2)));
    a.insertText('X');
    b.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(b.document.nodes[0].id, 2)));
    b.splitBlock();

    session.flush();
    expect(a.markdown, b.markdown);

    session.dispose();
    a.dispose();
    b.dispose();
  });

  test('turn-taking (flush between edits) also stays in sync', () {
    final a = MarkdownEditorController(markdown: 'X');
    final b = MarkdownEditorController(markdown: 'X');
    final session = OtCollaborationSession([a, b]);

    a.setSelection(caretAt(a, 1));
    a.insertText('A');
    session.flush();
    b.setSelection(caretAt(
        b, (b.document.nodes.first as TextBlockNode).delta.length));
    b.insertText('B');
    session.flush();

    expect(a.markdown, b.markdown);
    expect(a.markdown, 'XAB');

    session.dispose();
    a.dispose();
    b.dispose();
  });
}
