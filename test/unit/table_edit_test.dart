import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  MarkdownEditorController make() => MarkdownEditorController(
      markdown: '| A | B |\n| --- | --- |\n| 1 | 2 |');

  TableNode table(MarkdownEditorController c) => c.document.nodes.first as TableNode;

  test('updateTableCell changes a cell and round-trips', () {
    final c = make();
    final id = table(c).id;
    c.updateTableCell(id, 0, 0, 'Name');
    expect(table(c).cellText(0, 0), 'Name');
    expect(c.markdown, contains('| Name | B |'));
    c.dispose();
  });

  test('updateTableCell is undoable', () {
    final c = make();
    final id = table(c).id;
    c.updateTableCell(id, 1, 1, '99');
    expect(table(c).cellText(1, 1), '99');
    c.undo();
    expect(table(c).cellText(1, 1), '2');
    c.dispose();
  });

  test('addTableRow appends an empty row', () {
    final c = make();
    final id = table(c).id;
    c.addTableRow(id);
    expect(table(c).rowCount, 3); // header + 2 body rows
    expect(table(c).cellText(2, 0), '');
    c.dispose();
  });

  test('addTableColumn appends a column with alignment', () {
    final c = make();
    final id = table(c).id;
    c.addTableColumn(id);
    final t = table(c);
    expect(t.columnCount, 3);
    expect(t.alignments.length, 3);
    expect(t.rows.every((r) => r.length == 3), isTrue);
    c.dispose();
  });
}
