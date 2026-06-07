import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Drives the real delta IME path end-to-end: the editor's State *is* the
/// DeltaTextInputClient the platform calls, so we invoke
/// updateEditingValueWithDeltas directly with the deltas a real keyboard/IME
/// would send (insertion, deletion, replacement/autocorrect, composing).
void main() {
  Future<(MarkdownEditorController, DeltaTextInputClient)> pump(
    WidgetTester tester,
    String markdown,
  ) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: MarkdownEditor(controller: c, enableDrop: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
        find.byKey(ValueKey('markey-block-${c.document.nodes.first.id}')));
    await tester.pump();
    final client =
        tester.state(find.byType(MarkdownEditor)) as DeltaTextInputClient;
    return (c, client);
  }

  String firstText(MarkdownEditorController c) =>
      (c.document.nodes.first as TextBlockNode).delta.toPlainText();

  testWidgets('insertion delta inserts precisely at the offset', (tester) async {
    final (c, client) = await pump(tester, 'helo');
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaInsertion(
        oldText: 'helo',
        textInserted: 'l',
        insertionOffset: 3,
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(firstText(c), 'hello');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deletion delta removes the exact range', (tester) async {
    final (c, client) = await pump(tester, 'hello');
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaDeletion(
        oldText: 'hello',
        deletedRange: TextRange(start: 1, end: 3),
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(firstText(c), 'hlo');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('replacement delta (autocorrect) swaps a whole word',
      (tester) async {
    final (c, client) = await pump(tester, 'teh cat');
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaReplacement(
        oldText: 'teh cat',
        replacementText: 'the',
        replacedRange: TextRange(start: 0, end: 3),
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(firstText(c), 'the cat');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('deleting the block separator merges blocks (one stream)',
      (tester) async {
    // Two blocks → stream "aaa\nbbb"; the separator is global offset 3.
    final (c, client) = await pump(tester, 'aaa\n\nbbb');
    expect(c.document.length, 2);
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaDeletion(
        oldText: 'aaa\nbbb',
        deletedRange: TextRange(start: 3, end: 4), // the "\n" separator
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(c.document.length, 1);
    expect(firstText(c), 'aaabbb');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('inserting a newline mid-stream splits a block', (tester) async {
    final (c, client) = await pump(tester, 'aaabbb');
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaInsertion(
        oldText: 'aaabbb',
        textInserted: '\n',
        insertionOffset: 3,
        selection: TextSelection.collapsed(offset: 4),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(c.document.length, 2);
    expect((c.document.nodes[0] as TextBlockNode).delta.toPlainText(), 'aaa');
    expect((c.document.nodes[1] as TextBlockNode).delta.toPlainText(), 'bbb');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('composing-only delta keeps the text and tracks composition',
      (tester) async {
    final (c, client) = await pump(tester, 'abc');
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaNonTextUpdate(
        oldText: 'abc',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    ]);
    await tester.pump();
    expect(firstText(c), 'abc'); // unchanged
    expect(client.currentTextEditingValue?.composing,
        const TextRange(start: 0, end: 2));
    await tester.pumpWidget(const SizedBox());
  });
}
