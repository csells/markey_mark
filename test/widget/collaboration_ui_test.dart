import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end UI test: two live [MarkdownEditor]s wired by a
/// [CollaborationSession] — typing in one updates the other in real time.
void main() {
  testWidgets('an edit in one editor appears in the connected peer',
      (tester) async {
    final a = MarkdownEditorController(markdown: 'shared');
    final b = MarkdownEditorController(markdown: 'shared');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final session = CollaborationSession([a, b]);
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                  height: 200,
                  child: MarkdownEditor(
                      controller: a, key: const Key('editorA'))),
              SizedBox(
                  height: 200,
                  child: MarkdownEditor(
                      controller: b, key: const Key('editorB'))),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Focus editor A and type at the start of its block.
    await tester.tap(find.byKey(ValueKey('markey-block-${a.document.nodes.first.id}')));
    await tester.pump();
    a.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(a.document.nodes.first.id, 0)));
    await tester.pump();
    tester.testTextInput.enterText('X shared');
    await tester.pump();

    // The peer (b) received the edit and rebuilt.
    expect(b.markdown, 'X shared');
    expect(
      find.descendant(
        of: find.byKey(const Key('editorB')),
        matching:
            find.byKey(ValueKey('markey-block-${b.document.nodes.first.id}')),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disconnecting the session stops syncing', (tester) async {
    final a = MarkdownEditorController(markdown: 'a');
    final b = MarkdownEditorController(markdown: 'a');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final session = CollaborationSession([a, b]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 200, child: MarkdownEditor(controller: a)),
        ),
      ),
    );
    await tester.pump();
    expect(session.isActive, isTrue);

    session.dispose();
    expect(session.isActive, isFalse);

    await tester.tap(
        find.byKey(ValueKey('markey-block-${a.document.nodes.first.id}')));
    await tester.pump();
    a.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(a.document.nodes.first.id, 1)));
    await tester.pump();
    tester.testTextInput.enterText('a!');
    await tester.pump();

    // b stayed put because the session was disposed before the edit.
    expect(b.markdown, 'a');
    await tester.pumpWidget(const SizedBox());
  });
}
