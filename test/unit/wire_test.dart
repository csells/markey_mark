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
