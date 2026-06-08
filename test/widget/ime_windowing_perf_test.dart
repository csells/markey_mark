import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Strict UI-latency tests for the editing hot path. Best-in-class editors
/// (CodeMirror 6, ProseMirror, Lexical, super_editor) never reprocess the whole
/// document per keystroke — they work only on the changed/selection-local
/// region. These tests prove our IME is *windowed*: a keystroke flattens only
/// the active block, regardless of document size.
void main() {
  Future<(MarkdownEditorController, DeltaTextInputClient)> pump(
    WidgetTester tester,
    MarkdownEditorController c,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 500,
            child: MarkdownEditor(controller: c, enableDrop: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(MarkdownEditor));
    await tester.pump();
    final client =
        tester.state(find.byType(MarkdownEditor)) as DeltaTextInputClient;
    return (c, client);
  }

  String bigDoc(int blocks) =>
      List.generate(blocks, (i) => 'paragraph number $i here').join('\n\n');

  testWidgets('the IME mirrors a bounded window, not the whole document',
      (tester) async {
    final c =
        MarkdownEditorController(markdown: 'b0\n\nb1\n\nb2\n\nb3\n\nb4');
    addTearDown(c.dispose);
    final (_, client) = await pump(tester, c);

    // Caret in the middle block (b2 of 5).
    c.placeCaretAt(DocumentPosition.text(c.document.nodes[2].id, 0));
    await tester.pump();

    // The OS sees only the active block plus one neighbor each side (b1,b2,b3),
    // never the distant blocks b0 / b4.
    final imeText = client.currentTextEditingValue!.text;
    expect(imeText, 'b1\nb2\nb3');
    expect(imeText.contains('b0'), isFalse);
    expect(imeText.contains('b4'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a keystroke flattens only the active block (O(block), not O(doc))',
      (tester) async {
    final c = MarkdownEditorController(markdown: bigDoc(2000));
    addTearDown(c.dispose);
    final (_, client) = await pump(tester, c);

    // Caret in a middle block.
    final node = c.document.nodes[1000] as TextBlockNode;
    final blockLen = node.delta.length;
    c.placeCaretAt(DocumentPosition.text(node.id, blockLen));
    await tester.pump();

    // Measure exactly the flattening done by ONE keystroke.
    DocumentText.debugFlattenedChars = 0;
    client.updateEditingValueWithDeltas([
      TextEditingDeltaInsertion(
        oldText: node.delta.toPlainText(),
        textInserted: 'X',
        insertionOffset: blockLen,
        selection: TextSelection.collapsed(offset: blockLen + 1),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();

    // Windowed: bounded by a small constant × the block size (the active block
    // plus a neighbor on each side, rebuilt a couple of times). A whole-document
    // flatten would be ~2000 × that.
    expect(DocumentText.debugFlattenedChars, lessThan((blockLen + 10) * 12),
        reason: 'per-keystroke flattening must be O(block), not O(document)');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing latency is independent of document size', (tester) async {
    Future<int> typeBurst(int blocks) async {
      final c = MarkdownEditorController(markdown: bigDoc(blocks));
      addTearDown(c.dispose);
      final (_, client) = await pump(tester, c);
      final node = c.document.nodes[blocks ~/ 2] as TextBlockNode;
      var text = node.delta.toPlainText();
      c.placeCaretAt(DocumentPosition.text(node.id, text.length));
      await tester.pump();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 30; i++) {
        client.updateEditingValueWithDeltas([
          TextEditingDeltaInsertion(
            oldText: text,
            textInserted: 'z',
            insertionOffset: text.length,
            selection: TextSelection.collapsed(offset: text.length + 1),
            composing: TextRange.empty,
          ),
        ]);
        text = '${text}z';
        await tester.pump();
      }
      sw.stop();
      await tester.pumpWidget(const SizedBox());
      return sw.elapsedMicroseconds;
    }

    final small = await typeBurst(20);
    final large = await typeBurst(4000);
    // 200x more blocks must not make typing meaningfully slower. Generous
    // headroom for CI noise; a whole-doc flatten would blow this out.
    expect(large, lessThan(small * 8 + 200000),
        reason: 'small=$small us, large=$large us — typing must be ~constant');
  });
}
