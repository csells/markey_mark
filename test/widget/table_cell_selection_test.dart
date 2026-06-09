import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Rectangular cross-cell table selection: a selection whose anchor and extent
/// are in different cells highlights the whole rectangle of cells between them,
/// and the selected cell range can be copied as TSV.
void main() {
  Future<MarkdownEditorController> pump(WidgetTester tester) async {
    final c = MarkdownEditorController(
        markdown: '| a | b | c |\n|---|---|---|\n| d | e | f |\n| g | h | i |');
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
    return c;
  }

  DocumentPosition cell(String id, int r, int col) => DocumentPosition(
      nodeId: id, nodePosition: TableCellPosition(r, col, 0));

  Finder selected(String id, int r, int c) =>
      find.byKey(Key('markey-cell-selected-$id-$r-$c'));

  testWidgets('a cross-cell selection highlights the rectangle', (tester) async {
    final c = await pump(tester);
    final id = c.document.nodes.first.id;
    // Select from cell (0,0) to cell (1,1) → a 2x2 rectangle.
    c.setSelection(DocumentSelection(base: cell(id, 0, 0), extent: cell(id, 1, 1)));
    await tester.pump();

    for (final (r, col) in [(0, 0), (0, 1), (1, 0), (1, 1)]) {
      expect(selected(id, r, col), findsOneWidget,
          reason: 'cell ($r,$col) should be highlighted');
    }
    // Cells outside the rectangle are not highlighted.
    expect(selected(id, 0, 2), findsNothing);
    expect(selected(id, 2, 2), findsNothing);
  });

  testWidgets('a caret in one cell highlights no rectangle', (tester) async {
    final c = await pump(tester);
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection.collapsed(cell(id, 1, 1)));
    await tester.pump();
    expect(find.byKey(Key('markey-cell-selected-$id-1-1')), findsNothing);
  });

  testWidgets('Shift+tap extends the selection across cells', (tester) async {
    final c = await pump(tester);
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection.collapsed(cell(id, 0, 0)));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tap(find.byKey(Key('markey-cell-$id-1-2')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    final ext = c.selection!.extent.nodePosition as TableCellPosition;
    expect([ext.row, ext.col], [1, 2]);
    expect(selected(id, 1, 2), findsOneWidget);
  });

  test('the selected cell range serializes as TSV', () {
    final c = MarkdownEditorController(
        markdown: '| a | b | c |\n|---|---|---|\n| d | e | f |');
    addTearDown(c.dispose);
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection(base: cell(id, 0, 0), extent: cell(id, 1, 1)));
    expect(c.selectedTableCellsAsTsv(), 'a\tb\nd\te');
  });
}
