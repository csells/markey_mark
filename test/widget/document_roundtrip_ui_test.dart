import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end UI test: a rich document renders every block type through the
/// real widget, and toggling WYSIWYG ⇄ source (which runs the encoder/decoder)
/// preserves the Markdown. Exercises the model/render/serializer stack via UI.
void main() {
  const richDoc = '''
# Heading

para with **bold**, _italic_ and ==mark==

- bullet
- [x] done

1. first
2. second

> [!NOTE]
> a callout

> a quote

`code` and a [link](https://x.dev)

| a | b |
| :--- | ---: |
| 1 | 2 |

\$\$
x^2
\$\$

---

term
: definition
''';

  testWidgets('renders a rich document and round-trips through source mode',
      (tester) async {
    final c = MarkdownEditorController(markdown: richDoc);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 1500,
            child: MarkdownEditor(controller: c),
          ),
        ),
      ),
    );
    await tester.pump();

    // A representative set of block widgets rendered in the viewport.
    expect(find.byType(Table), findsOneWidget); // GFM table
    expect(find.byType(Checkbox), findsOneWidget); // task item
    expect(find.text('•'), findsOneWidget); // bullet marker
    expect(find.byType(Math), findsWidgets); // block math (flutter_math_fork)

    // The decoder produced every block type from the Markdown.
    final types = c.document.nodes.map((n) => n.runtimeType.toString()).toSet();
    expect(types, containsAll(<String>[
      'TextBlockNode',
      'TableNode',
      'MathBlockNode',
      'HorizontalRuleNode',
    ]));

    final before = c.markdown;

    // Toggle to source (runs the encoder) and back (runs the decoder).
    await tester.tap(find.byKey(const Key('markey_toggle_mode')));
    await tester.pump();
    expect(find.byKey(const Key('markey_source_field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('markey_toggle_mode')));
    await tester.pump();

    // Content preserved across the WYSIWYG⇄source round trip.
    expect(c.markdown, before);
    expect(find.byType(Table), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
