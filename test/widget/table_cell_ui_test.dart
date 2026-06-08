import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Step 5 (tables): cells are sub-editors of the ONE editor — they render with
/// the shared caret (no per-cell TextField) and edit through the unified
/// IME/command pipeline via [TableCellPosition].
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
            width: 700,
            height: 400,
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

  String cell(MarkdownEditorController c, int r, int col) =>
      (c.document.nodes.first as TableNode).rows[r][col].toPlainText();

  testWidgets('cells render without a TextField', (tester) async {
    await pump(tester, '| A | B |\n| --- | --- |\n| 1 | 2 |');
    expect(find.byType(EditableText), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('typing in a cell edits that cell via the unified IME',
      (tester) async {
    final (c, client) = await pump(tester, '| A | B |\n| --- | --- |\n| 1 | 2 |');
    final id = c.document.nodes.first.id;
    // Put the caret at the end of cell (1,0) = "1".
    c.placeCaretAt(DocumentPosition(
        nodeId: id, nodePosition: const TableCellPosition(1, 0, 1)));
    await tester.pump();
    client.updateEditingValueWithDeltas(const [
      TextEditingDeltaInsertion(
        oldText: '1',
        textInserted: '0',
        insertionOffset: 1,
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();
    expect(cell(c, 1, 0), '10');
    expect(cell(c, 1, 1), '2'); // sibling untouched
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping a cell places the caret inside it', (tester) async {
    final c = MarkdownEditorController(
        markdown: '| A | B |\n| --- | --- |\n| 1 | 2 |');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 700,
              height: 400,
              child: MarkdownEditor(controller: c, enableDrop: false)),
        ),
      ),
    );
    await tester.pump();
    final id = c.document.nodes.first.id;
    await tester.tap(find.byKey(Key('markey-cell-$id-1-1')));
    await tester.pump();
    final ext = c.selection!.extent;
    expect(ext.nodeId, id);
    expect(ext.nodePosition, isA<TableCellPosition>());
    expect((ext.nodePosition as TableCellPosition).row, 1);
    expect((ext.nodePosition as TableCellPosition).col, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
