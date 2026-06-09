import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end proof that the plugin API is sufficient to add a brand-new block
/// type: a `CustomBlockCodec` makes it round-trip through Markdown, and a
/// `BlockRegistry` renderer draws it — no fork of the editor required.
void main() {
  // A "rating" block: ```rating\n4\n``` ⇄ CustomBlockNode(data: {stars: 4}).
  final codecs = BlockCodecs([
    CustomBlockCodec(
      blockType: 'rating',
      fence: 'rating',
      decode: (content) => {'stars': int.tryParse(content.trim()) ?? 0},
      encode: (node) => '${node.data['stars']}',
    ),
  ]);

  final registry = BlockRegistry({
    'rating': (context, node, style) => Row(
          key: ValueKey('rating-${node.id}'),
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            node.data['stars'] as int,
            (_) => const Icon(Icons.star),
          ),
        ),
  });

  testWidgets('a custom block parses, renders, and round-trips', (tester) async {
    final c = MarkdownEditorController(
        markdown: '# Review\n\n```rating\n4\n```', codecs: codecs);
    addTearDown(c.dispose);

    // Parsed into a CustomBlockNode (not a code block).
    final custom = c.document.nodes.whereType<CustomBlockNode>().single;
    expect(custom.blockType, 'rating');
    expect(custom.data['stars'], 4);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            height: 300,
            child: MarkdownEditor(
              controller: c,
              enableDrop: false,
              blockRegistry: registry,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The registry renderer drew the block (4 stars).
    expect(find.byKey(ValueKey('rating-${custom.id}')), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(4));

    // It serializes back to the same Markdown.
    expect(c.markdown, '# Review\n\n```rating\n4\n```');
  });
}
