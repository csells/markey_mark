import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Touch selection handles + magnifier — the mobile editing affordances a
/// hand-painted editor must provide itself (EditableText gets them free). On
/// touch platforms a non-collapsed selection shows draggable endpoint handles
/// (reusing Material's handle visuals); dragging a handle moves that end of the
/// selection, and a magnifier loupe appears during the drag.
void main() {
  Future<MarkdownEditorController> pump(
      WidgetTester tester, String markdown) async {
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
    return c;
  }

  testWidgets('a non-collapsed selection shows two drag handles on touch',
      (tester) async {
    final c = await pump(tester, 'hello world');
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(id, 0),
      extent: DocumentPosition.text(id, 5),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('markey_handle_start')), findsOneWidget);
    expect(find.byKey(const Key('markey_handle_end')), findsOneWidget);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('a collapsed caret shows no handles', (tester) async {
    final c = await pump(tester, 'hello world');
    final id = c.document.nodes.first.id;
    c.placeCaretAt(DocumentPosition.text(id, 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('markey_handle_start')), findsNothing);
    expect(find.byKey(const Key('markey_handle_end')), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('dragging the end handle moves the selection extent',
      (tester) async {
    final c = await pump(tester, 'hello world');
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(id, 0),
      extent: DocumentPosition.text(id, 9),
    ));
    await tester.pumpAndSettle();

    final before =
        (c.selection!.extent.nodePosition as TextNodePosition).offset;
    // Drag the end handle left → the extent should shrink toward the anchor.
    await tester.drag(
        find.byKey(const Key('markey_handle_end')), const Offset(-120, 0));
    await tester.pumpAndSettle();

    final after = (c.selection!.extent.nodePosition as TextNodePosition).offset;
    expect(c.selection!.base.nodeId, id);
    expect(after, lessThan(before));
    expect(c.selection!.isCollapsed, isFalse);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('a magnifier appears while dragging a handle', (tester) async {
    final c = await pump(tester, 'hello world here');
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(id, 0),
      extent: DocumentPosition.text(id, 11),
    ));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('markey_handle_end'))));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(find.byKey(const Key('markey_magnifier')), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('markey_magnifier')), findsNothing);
  }, variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.android, TargetPlatform.iOS}));
}
