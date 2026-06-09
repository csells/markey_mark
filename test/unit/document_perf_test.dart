import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Strict performance gates for the document edit path. A keystroke must be
/// O(log n) (persistent-tree edit) + O(1) id lookup — never O(document). These
/// gates fail loudly if `Document` regresses to linear id scans or whole-list
/// copy-on-write.
void main() {
  Document bigDoc(int n) => Document([
        for (var i = 0; i < n; i++)
          TextBlockNode.paragraph(id: 'n$i', delta: Delta.text('block $i text')),
      ]);

  test('id lookup is O(1): typing adds no linear scans after priming', () {
    final c = MarkdownEditorController();
    c.setDocument(bigDoc(5000));
    final midId = 'n2500';
    c.placeCaretAt(DocumentPosition.text(midId, 0));

    // Prime any lazy index, then measure scans across many keystrokes.
    c.document.indexOfId(midId);
    Document.debugIdScans = 0;
    for (var i = 0; i < 100; i++) {
      c.placeCaretAt(DocumentPosition.text(midId, i));
      c.insertText('x');
    }
    // No re-scan of the 5000-element document on edits (cache carried across
    // structure-preserving replaces).
    expect(Document.debugIdScans, lessThan(5000),
        reason: '100 keystrokes must not each scan 5000 nodes');
    c.dispose();
  });

  test('typing latency is independent of document size (O(log n) edits)', () {
    int typeBurst(int blocks) {
      final c = MarkdownEditorController();
      c.setDocument(bigDoc(blocks));
      final midId = 'n${blocks ~/ 2}';
      final sw = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        c.placeCaretAt(DocumentPosition.text(midId, i));
        c.insertText('x');
      }
      sw.stop();
      c.dispose();
      return sw.elapsedMicroseconds;
    }

    final small = typeBurst(200);
    final huge = typeBurst(100000);
    // 500x the blocks must not blow up typing time. A flat-list O(n) copy /
    // linear id scan would make `huge` dramatically slower.
    expect(huge, lessThan(small * 10 + 500000),
        reason: 'small=$small us, huge=$huge us — editing must be ~O(log n)');
  });
}
