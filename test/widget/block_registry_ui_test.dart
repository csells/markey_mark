import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// The open block set (§13.5 / ADR-008): a host can register a renderer for a
/// custom block type and the editor renders [CustomBlockNode]s through it —
/// without editing the core's block switches.
void main() {
  testWidgets('a registered custom block renders via its builder',
      (tester) async {
    final c = MarkdownEditorController();
    addTearDown(c.dispose);
    // Seed a document containing a custom block.
    c.setDocument(Document([
      TextBlockNode.paragraph(delta: Delta.text('before')),
      CustomBlockNode(blockType: 'rating', data: const {'stars': 4}),
      TextBlockNode.paragraph(delta: Delta.text('after')),
    ]));

    final registry = BlockRegistry()
      ..register('rating', (context, node, style) {
        return Text('★ ${node.data['stars']}',
            key: const Key('custom-rating'));
      });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: MarkdownEditor(
                controller: c, blockRegistry: registry, enableDrop: false),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('custom-rating')), findsOneWidget);
    expect(find.text('★ 4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unregistered custom block degrades without throwing',
      (tester) async {
    final c = MarkdownEditorController();
    addTearDown(c.dispose);
    c.setDocument(Document([CustomBlockNode(blockType: 'unknown')]));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 400, height: 200, child: MarkdownEditor(controller: c, enableDrop: false)),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
