import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Step 5: a code block is part of the ONE editor — editing it routes through
/// the same unified IME/stream/command pipeline as text blocks (no separate
/// TextField), and it renders with the shared caret.
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
    await tester.tap(find.byType(MarkdownEditor));
    await tester.pump();
    final client =
        tester.state(find.byType(MarkdownEditor)) as DeltaTextInputClient;
    return (c, client);
  }

  String code(MarkdownEditorController c) =>
      (c.document.nodes.first as CodeBlockNode).code;

  testWidgets('typing in a code block updates its code via the unified IME',
      (tester) async {
    final (c, client) = await pump(tester, '```\nabc\n```');
    expect(c.document.nodes.first, isA<CodeBlockNode>());
    // Stream == "abc"; insert "X" at global offset 1.
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaInsertion(
        oldText: 'abc',
        textInserted: 'X',
        insertionOffset: 1,
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(code(c), 'aXbc');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Enter in a code block inserts a newline (stays one block)',
      (tester) async {
    final (c, client) = await pump(tester, '```\nab\n```');
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaInsertion(
        oldText: 'ab',
        textInserted: '\n',
        insertionOffset: 1,
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(c.document.length, 1);
    expect(code(c), 'a\nb');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the code block renders with the unified caret painter (no TextField)',
      (tester) async {
    final c = MarkdownEditorController(markdown: '```\nx\n```');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 600,
              height: 200,
              child: MarkdownEditor(controller: c, enableDrop: false)),
        ),
      ),
    );
    await tester.pump();
    // The code block is editable through the shared surface, not a TextField.
    expect(find.byType(EditableText), findsNothing);
    expect(find.byKey(ValueKey('markey-code-${c.document.nodes.first.id}')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
