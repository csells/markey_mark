import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';
import 'package:markey_mark/src/widget/ime_delta.dart';

/// The IME window (extracted, pure): the OS sees only the selection's editable
/// block(s) plus one editable neighbour each side — never the whole document —
/// so a keystroke stays O(selection span + 2).
void main() {
  Document doc(int n) => Document([
        for (var i = 0; i < n; i++)
          TextBlockNode.paragraph(id: 'n$i', delta: Delta.text('b$i')),
      ]);

  DocumentSelection caret(String id, int o) =>
      DocumentSelection.collapsed(DocumentPosition.text(id, o));

  test('windows to the active block plus one neighbour each side', () {
    final w = imeWindow(doc(5), caret('n2', 0))!;
    expect(w.text, 'b1\nb2\nb3'); // n1, n2, n3 only
  });

  test('clamps at the document start', () {
    final w = imeWindow(doc(5), caret('n0', 0))!;
    expect(w.text, 'b0\nb1');
  });

  test('clamps at the document end', () {
    final w = imeWindow(doc(5), caret('n4', 0))!;
    expect(w.text, 'b3\nb4');
  });

  test('a cross-block selection spans both ends plus neighbours', () {
    final d = doc(6);
    final w = imeWindow(
        d, DocumentSelection(base: DocumentPosition.text('n1', 0),
            extent: DocumentPosition.text('n3', 0)))!;
    expect(w.text, 'b0\nb1\nb2\nb3\nb4');
  });

  test('null selection windows to the document start', () {
    expect(imeWindow(doc(3), null)!.text, 'b0\nb1');
  });

  test('a selection on a missing node falls back to the start', () {
    expect(imeWindow(doc(3), caret('gone', 0))!.text, 'b0\nb1');
  });

  test('skips non-editable blocks in the window', () {
    final d = Document([
      ImageNode(id: 'img', url: 'a.png'),
      TextBlockNode.paragraph(id: 't', delta: Delta.text('hi')),
    ]);
    final w = imeWindow(d, caret('t', 0))!;
    expect(w.text, 'hi'); // image skipped
  });

  test('returns null when there is no editable block in range', () {
    final d = Document([ImageNode(id: 'img', url: 'a.png')]);
    expect(imeWindow(d, caret('img', 0)), isNull);
  });

  test('includes a code block as editable', () {
    final d = Document([
      TextBlockNode.paragraph(id: 'p', delta: Delta.text('x')),
      CodeBlockNode(id: 'c', code: 'y'),
    ]);
    expect(imeWindow(d, caret('c', 0))!.text, 'x\ny');
  });
}
