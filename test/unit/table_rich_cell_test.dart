import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  MarkdownEditorController make() =>
      MarkdownEditorController(markdown: '| A | B |\n| --- | --- |\n| 1 | 2 |');

  TableNode table(MarkdownEditorController c) =>
      c.document.nodes.first as TableNode;

  test('updateTableCell parses inline markdown into a rich cell', () {
    final c = make();
    c.updateTableCell(table(c).id, 1, 0, 'has **bold** text');
    final cell = table(c).rows[1][0];
    expect(cell.toPlainText(), 'has bold text');
    expect(cell.isFormatted(4, 8, 'bold'), isTrue);
    expect(c.markdown, contains('| has **bold** text | 2 |'));
    c.dispose();
  });

  test('cellMarkdown returns the inline markdown for a cell', () {
    final c = make();
    c.updateTableCell(table(c).id, 0, 0, 'a [link](http://x)');
    expect(c.cellMarkdown(table(c).id, 0, 0), 'a [link](http://x)');
    c.dispose();
  });

  test('plain text still works (no markdown)', () {
    final c = make();
    c.updateTableCell(table(c).id, 0, 1, 'Plain');
    expect(table(c).cellText(0, 1), 'Plain');
    c.dispose();
  });
}
