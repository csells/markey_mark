import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Tab / Shift+Tab move the caret between table cells (row-major, wrapping),
/// and Tab off the last cell appends a new row — the spreadsheet-style cell
/// navigation a table editor needs.
void main() {
  Future<MarkdownEditorController> pump(WidgetTester tester) async {
    final c = MarkdownEditorController(
        markdown: '| h1 | h2 |\n| --- | --- |\n| a | b |');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
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

  TableCellPosition cellOf(MarkdownEditorController c) =>
      c.selection!.extent.nodePosition as TableCellPosition;

  Future<void> tab(WidgetTester tester, {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
  }

  testWidgets('Tab advances across cells, wrapping to the next row',
      (tester) async {
    final c = await pump(tester);
    final id = c.document.nodes.first.id;
    c.placeCaretAt(DocumentPosition(
        nodeId: id, nodePosition: const TableCellPosition(0, 0, 0)));
    await tester.pump();

    await tab(tester);
    expect([cellOf(c).row, cellOf(c).col], [0, 1]); // h1 -> h2
    await tab(tester);
    expect([cellOf(c).row, cellOf(c).col], [1, 0]); // wrap to next row, a
    await tab(tester);
    expect([cellOf(c).row, cellOf(c).col], [1, 1]); // b
  });

  testWidgets('Shift+Tab moves back across cells', (tester) async {
    final c = await pump(tester);
    final id = c.document.nodes.first.id;
    c.placeCaretAt(DocumentPosition(
        nodeId: id, nodePosition: const TableCellPosition(1, 0, 0)));
    await tester.pump();
    await tab(tester, shift: true);
    expect([cellOf(c).row, cellOf(c).col], [0, 1]); // back-wrap to prev row end
  });

  testWidgets('Tab off the last cell appends a new row', (tester) async {
    final c = await pump(tester);
    final id = c.document.nodes.first.id;
    final before = (c.document.nodeById(id) as TableNode).rowCount;
    c.placeCaretAt(DocumentPosition(
        nodeId: id, nodePosition: const TableCellPosition(1, 1, 0)));
    await tester.pump();
    await tab(tester);
    final after = (c.document.nodeById(id) as TableNode).rowCount;
    expect(after, before + 1);
    expect([cellOf(c).row, cellOf(c).col], [before, 0]); // first cell of new row
  });
}
