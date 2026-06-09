import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

void main() {
  Future<MarkdownEditorController> pump(
    WidgetTester tester, {
    bool enableDrop = true,
    bool readOnly = false,
  }) async {
    final c = MarkdownEditorController(markdown: 'hello');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MarkdownEditor(
              controller: c,
              enableDrop: enableDrop,
              readOnly: readOnly,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  testWidgets('a DropRegion wraps the editor when drop is enabled',
      (tester) async {
    await pump(tester);
    expect(find.byType(DropRegion), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no DropRegion when drop is disabled', (tester) async {
    await pump(tester, enableDrop: false);
    expect(find.byType(DropRegion), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('read-only editors do not accept drops', (tester) async {
    await pump(tester, readOnly: true);
    expect(find.byType(DropRegion), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('applyDrop on the live editor inserts and re-renders',
      (tester) async {
    final c = await pump(tester);
    c.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(c.document.nodes.first.id, 5)));
    await tester.pump();
    c.applyDrop(const [DroppedItem.image('dropped.png', alt: 'dropped')]);
    await tester.pump();
    expect(c.document.nodes.whereType<ImageNode>().length, 1);
    expect(find.byType(Image), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
