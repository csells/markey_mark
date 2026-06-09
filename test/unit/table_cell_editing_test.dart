import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/editing/commands.dart';
import 'package:markey_mark/src/model/delta.dart';
import 'package:markey_mark/src/model/document.dart';
import 'package:markey_mark/src/model/node.dart';
import 'package:markey_mark/src/model/position.dart';
import 'package:markey_mark/src/model/selection.dart';

/// Step 5 (tables): a table cell is a sub-editor that shares the command
/// pipeline. A [TableCellPosition] addresses (row, col, offset); edits operate
/// on that cell's Delta and never merge across cells.
void main() {
  TableNode table(String id) => TableNode(
        id: id,
        rows: [
          [Delta.text('a'), Delta.text('b')],
          [Delta.text('c'), Delta.text('d')],
        ],
        alignments: const [TableAlign.none, TableAlign.none],
      );

  DocumentSelection cellCaret(String id, int r, int col, int o) =>
      DocumentSelection.collapsed(
          DocumentPosition(nodeId: id, nodePosition: TableCellPosition(r, col, o)));

  DocumentSelection cellRange(String id, int r, int col, int a, int b) =>
      DocumentSelection(
        base: DocumentPosition(nodeId: id, nodePosition: TableCellPosition(r, col, a)),
        extent: DocumentPosition(nodeId: id, nodePosition: TableCellPosition(r, col, b)),
      );

  String cell(Document d, String id, int r, int col) =>
      (d.nodeById(id) as TableNode).rows[r][col].toPlainText();

  test('TableCellPosition equality/toString', () {
    expect(const TableCellPosition(0, 1, 2), const TableCellPosition(0, 1, 2));
    expect(const TableCellPosition(0, 1, 2) == const TableCellPosition(1, 1, 2),
        isFalse);
  });

  test('insertText edits the addressed cell', () {
    final doc = Document([table('t')]);
    final txn = EditCommands.insertText(doc, cellCaret('t', 1, 0, 1), 'X')!;
    final after = txn.apply(doc);
    expect(cell(after, 't', 1, 0), 'cX');
    expect(cell(after, 't', 0, 0), 'a'); // others untouched
    expect(txn.selectionAfter,
        cellCaret('t', 1, 0, 2));
  });

  test('insertText replaces a within-cell range', () {
    final doc = Document([
      TableNode(
        id: 't',
        rows: [
          [Delta.text('hello'), Delta.text('x')],
        ],
        alignments: const [TableAlign.none, TableAlign.none],
      )
    ]);
    final txn = EditCommands.insertText(doc, cellRange('t', 0, 0, 1, 4), 'Y')!;
    expect(cell(txn.apply(doc), 't', 0, 0), 'hYo');
  });

  test('deleteBackward removes the char before the cell caret', () {
    final doc = Document([table('t')]);
    final txn = EditCommands.deleteBackward(doc, cellCaret('t', 0, 1, 1))!;
    expect(cell(txn.apply(doc), 't', 0, 1), '');
  });
}
