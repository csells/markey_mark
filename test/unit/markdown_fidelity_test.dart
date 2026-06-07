import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Fidelity (structure-preserving) round-trip tests: a paragraph whose text
/// merely *looks* like a block marker must stay a paragraph, nested ordered
/// lists must stay nested, and inline marks inside table cells must survive.
void main() {
  TextBlockNode para(String text) =>
      TextBlockNode.paragraph(delta: Delta.text(text));

  String typeOfFirst(String md) =>
      (Markdown.parse(md).nodes.first as TextBlockNode).type;

  group('paragraph text that looks like a block marker stays a paragraph', () {
    for (final text in [
      '# not a heading',
      '## still text',
      '> not a quote',
      '- not a bullet',
      '+ not a bullet',
      '1. not ordered',
      '3) not ordered',
    ]) {
      test('"$text"', () {
        final md = Markdown.serialize(Document([para(text)]));
        final reparsed = Markdown.parse(md);
        expect(reparsed.nodes.length, 1);
        final node = reparsed.nodes.first as TextBlockNode;
        expect(node.type, BlockType.paragraph, reason: 'serialized as: $md');
        expect(node.delta.toPlainText(), text);
      });
    }
  });

  test('a heading still serializes normally (escaping is leading-only)', () {
    final md = Markdown.serialize(
        Document([TextBlockNode.heading(level: 2, delta: Delta.text('Title'))]));
    expect(md, '## Title');
    expect(typeOfFirst(md), BlockType.heading);
  });

  test('nested ordered lists stay nested across a round trip', () {
    final doc = Document([
      TextBlockNode.numbered(number: 1, delta: Delta.text('a')),
      TextBlockNode.numbered(number: 1, delta: Delta.text('b'), indent: 1),
    ]);
    final md = Markdown.serialize(doc);
    final reparsed = Markdown.parse(md);
    final items =
        reparsed.nodes.cast<TextBlockNode>().where((n) => n.number != null).toList();
    expect(items.length, 2);
    expect(items[1].indent, 1, reason: 'serialized as: $md');
  });

  test('raw HTML block is preserved verbatim (not re-escaped)', () {
    const src = '<div class="x">\n*not emphasis*\n</div>';
    final doc = Markdown.parse(src);
    expect(doc.nodes.single, isA<HtmlBlockNode>());
    final out = Markdown.serialize(doc);
    expect(out, src);
    // Stable: no escalating backslash escaping across passes.
    expect(Markdown.serialize(Markdown.parse(out)), out);
  });

  test('raw HTML block exports to HTML verbatim', () {
    final doc = Markdown.parse('<div><span>hi</span></div>');
    expect(Markdown.toHtml(doc), '<div><span>hi</span></div>');
  });

  test('inline marks inside a table cell survive a round trip', () {
    final doc = Document([
      TableNode(
        rows: [
          [Delta.text('h1'), Delta.text('h2')],
          [
            Delta([TextRun('bold', {InlineAttr.bold: true})]),
            Delta.text('plain'),
          ],
        ],
        alignments: [TableAlign.left, TableAlign.left],
      ),
    ]);
    final md = Markdown.serialize(doc);
    final table = Markdown.parse(md).nodes.whereType<TableNode>().single;
    expect(table.rows[1][0].isFormatted(0, 4, 'bold'), isTrue,
        reason: 'serialized as: $md');
  });
}
