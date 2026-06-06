import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  DocumentSelection caret(MarkdownEditorController c, int o) =>
      DocumentSelection.collapsed(
          DocumentPosition.text(c.document.nodes.first.id, o));

  group('CollaborationSession', () {
    test('a local edit on one peer appears on the other', () {
      final a = MarkdownEditorController(markdown: 'Shared doc');
      final b = MarkdownEditorController(markdown: 'Shared doc');
      final session = CollaborationSession([a, b]);

      a.setSelection(caret(a, 10));
      a.insertText('!');
      expect(a.markdown, 'Shared doc!');
      expect(b.markdown, 'Shared doc!'); // synced to peer b

      session.dispose();
      a.dispose();
      b.dispose();
    });

    test('edits flow both ways and stay in sync', () {
      final a = MarkdownEditorController(markdown: 'X');
      final b = MarkdownEditorController(markdown: 'X');
      final session = CollaborationSession([a, b]);

      a.setSelection(caret(a, 1));
      a.insertText('A');
      b.setSelection(caret(
          b, (b.document.nodes.first as TextBlockNode).delta.length));
      b.insertText('B');

      expect(a.markdown, b.markdown);
      expect(a.markdown, 'XAB');

      session.dispose();
      a.dispose();
      b.dispose();
    });

    test('remote edits do not echo back (no infinite loop)', () {
      final a = MarkdownEditorController(markdown: 'hi');
      final b = MarkdownEditorController(markdown: 'hi');
      final session = CollaborationSession([a, b]);
      var aEdits = 0;
      a.outgoing.listen((_) => aEdits++);

      b.setSelection(caret(b, 2));
      b.insertText('!');
      // a received b's edit but must not re-broadcast it.
      expect(a.markdown, 'hi!');
      expect(aEdits, 0);

      session.dispose();
      a.dispose();
      b.dispose();
    });

    test('a disposed session stops syncing', () {
      final a = MarkdownEditorController(markdown: 'p');
      final b = MarkdownEditorController(markdown: 'p');
      CollaborationSession([a, b]).dispose();
      a.setSelection(caret(a, 1));
      a.insertText('Q');
      expect(a.markdown, 'pQ');
      expect(b.markdown, 'p'); // no longer synced
      a.dispose();
      b.dispose();
    });
  });
}
