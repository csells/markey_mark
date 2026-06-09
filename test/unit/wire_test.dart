import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Wire serialization for collaboration: edit transactions (and the nodes they
/// carry) round-trip through JSON so a real network transport can carry them
/// between peers. Node ids are preserved (OT needs stable ids across the wire).
void main() {
  group('node round-trips', () {
    void rt(Node node) {
      final json = CollaborationWire.nodeToJson(node);
      final back = CollaborationWire.nodeFromJson(json);
      expect(back, node, reason: '$node did not round-trip');
      expect(back.id, node.id);
    }

    test('text blocks (paragraph, heading, list, todo) with marks', () {
      rt(TextBlockNode.paragraph(
          id: 'p', delta: Delta.text('hi', const {InlineAttr.bold: true})));
      rt(TextBlockNode.heading(id: 'h', level: 2, delta: Delta.text('Title')));
      rt(TextBlockNode.bullet(id: 'b', delta: Delta.text('item')));
      rt(TextBlockNode.todo(id: 't', checked: true, delta: Delta.text('done')));
    });
    test('code, image, hr, math, mermaid, html, custom', () {
      rt(CodeBlockNode(id: 'c', code: 'x=1', language: 'dart'));
      rt(ImageNode(id: 'i', url: 'a.png', alt: 'a', title: 't'));
      rt(HorizontalRuleNode(id: 'r'));
      rt(MathBlockNode(id: 'm', tex: 'x^2'));
      rt(MermaidNode(id: 'd', source: 'graph TD'));
      rt(CustomBlockNode(id: 'k', blockType: 'chart', data: const {'n': 3}));
    });
    test('tables', () {
      rt(TableNode(
        id: 'tab',
        rows: [
          [Delta.text('h1'), Delta.text('h2')],
          [Delta.text('a'), Delta.text('b')],
        ],
        alignments: const [TableAlign.left, TableAlign.right],
      ));
    });
    test('front-matter and html blocks', () {
      rt(FrontMatterNode(id: 'fm', yaml: 'title: hi'));
      rt(HtmlBlockNode(id: 'h', html: '<div>x</div>'));
    });
  });

  test('transaction with selectionBefore + a table-cell selection round-trips',
      () {
    final txn = EditTransaction(
      operations: [
        InsertNodeOp(0, TextBlockNode.paragraph(id: 'p', delta: Delta.text('x')))
      ],
      selectionBefore: const DocumentSelection.collapsed(DocumentPosition(
          nodeId: 't', nodePosition: TableCellPosition(1, 2, 3))),
      selectionAfter: const DocumentSelection(
        base: DocumentPosition(
            nodeId: 'i', nodePosition: AtomicNodePosition.upstream()),
        extent: DocumentPosition(
            nodeId: 'i', nodePosition: AtomicNodePosition.downstream()),
      ),
    );
    final back = CollaborationWire.decode(CollaborationWire.encode(txn));
    final cell = back.selectionBefore!.extent.nodePosition as TableCellPosition;
    expect([cell.row, cell.col, cell.offset], [1, 2, 3]);
    expect(back.selectionAfter!.base.nodePosition, isA<AtomicNodePosition>());
  });

  test('transaction round-trips through JSON', () {
    final before = TextBlockNode.paragraph(id: 'p', delta: Delta.text('hi'));
    final after = TextBlockNode.paragraph(id: 'p', delta: Delta.text('hiX'));
    final txn = EditTransaction(
      operations: [
        ReplaceNodeOp(0, before, after),
        InsertNodeOp(1, CodeBlockNode(id: 'c', code: 'y')),
        DeleteNodeOp(2, ImageNode(id: 'i', url: 'z.png')),
      ],
      selectionAfter:
          DocumentSelection.collapsed(DocumentPosition.text('p', 3)),
      tag: 'typing',
    );
    final s = CollaborationWire.encode(txn);
    expect(s, isA<String>());
    final back = CollaborationWire.decode(s);
    expect(back.operations.length, 3);
    expect(back.tag, 'typing');
    // Applying the decoded transaction matches applying the original.
    final base = Document([before]);
    expect(txn.apply(base), back.apply(base));
    expect((back.selectionAfter!.extent.nodePosition as TextNodePosition).offset,
        3);
  });

  test('decode throws on unknown op / node kinds', () {
    expect(() => CollaborationWire.operationFromJson({'op': '?', 'index': 0}),
        throwsArgumentError);
    expect(() => CollaborationWire.nodeFromJson({'id': 'x', 'k': '?'}),
        throwsArgumentError);
  });

  test('a TransportCollaborationSession can be disposed', () {
    final c = MarkdownEditorController(markdown: 'x');
    addTearDown(c.dispose);
    final link = LoopbackTransportPair();
    final session = TransportCollaborationSession(c, link.a);
    session.dispose();
    link.dispose();
  });

  testWidgets('edits sync between two peers over a loopback transport',
      (tester) async {
    final a = MarkdownEditorController(markdown: 'shared');
    final b = MarkdownEditorController(markdown: 'shared');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    // A loopback transport: whatever A sends, B receives, and vice-versa.
    final link = LoopbackTransportPair();
    TransportCollaborationSession(a, link.a);
    TransportCollaborationSession(b, link.b);

    a.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(a.document.nodes.first.id, 6)));
    a.insertText('!');
    await tester.pump();

    expect(a.markdown, 'shared!');
    expect(b.markdown, 'shared!'); // arrived over the wire (serialized)
  });
}
