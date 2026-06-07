import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end UI tests for block reordering via drag handles.
void main() {
  Future<MarkdownEditorController> pump(
    WidgetTester tester,
    String markdown, {
    bool readOnly = false,
  }) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 500,
            child: MarkdownEditor(controller: c, readOnly: readOnly),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  List<String> order(MarkdownEditorController c) => c.document.nodes
      .map((n) => (n as TextBlockNode).delta.toPlainText())
      .toList();

  testWidgets('each block shows a drag handle', (tester) async {
    final c = await pump(tester, 'a\n\nb');
    for (final n in c.document.nodes) {
      expect(find.byKey(ValueKey('markey-drag-${n.id}')), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dragging a block handle onto a later block reorders it',
      (tester) async {
    final c = await pump(tester, 'a\n\nb\n\nc');
    final aId = c.document.nodes.first.id;
    final cId = c.document.nodes.last.id;
    final handle = find.byKey(ValueKey('markey-drag-$aId'));
    final targetCenter =
        tester.getCenter(find.byKey(ValueKey('markey-block-$cId')));
    final from = tester.getCenter(handle);

    await tester.drag(handle, targetCenter - from);
    await tester.pumpAndSettle();

    expect(order(c), ['b', 'c', 'a']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-only editors have no drag handles', (tester) async {
    final c = await pump(tester, 'a\n\nb', readOnly: true);
    expect(find.byKey(ValueKey('markey-drag-${c.document.nodes.first.id}')),
        findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
