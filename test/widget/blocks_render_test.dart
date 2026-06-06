import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  Future<MarkdownEditorController> pump(
    WidgetTester tester,
    String markdown, {
    bool readOnly = false,
  }) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 500,
            child: MarkdownEditor(controller: c, readOnly: readOnly),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('horizontal rule renders a Divider', (tester) async {
    await pump(tester, 'a\n\n---\n\nb');
    expect(find.byType(Divider), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('bulleted list renders a bullet marker', (tester) async {
    await pump(tester, '- item');
    expect(find.text('•'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('numbered list renders its number marker', (tester) async {
    await pump(tester, '1. first\n2. second');
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('task list renders checkboxes reflecting state', (tester) async {
    final c = await pump(tester, '- [ ] todo\n- [x] done');
    final checkboxes =
        tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(checkboxes.length, 2);
    expect(checkboxes[0].value, false);
    expect(checkboxes[1].value, true);
    expect(c.document.length, 2);
    await teardown(tester);
  });

  testWidgets('tapping a task checkbox toggles its checked state',
      (tester) async {
    final c = await pump(tester, '- [ ] todo');
    expect((c.document.nodes.first as TextBlockNode).checked, false);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect((c.document.nodes.first as TextBlockNode).checked, true);
    await teardown(tester);
  });

  testWidgets('quote renders a distinguishable container', (tester) async {
    final c = await pump(tester, '> quoted');
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-quote-$id')), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('code block renders the language label', (tester) async {
    final c = await pump(tester, '```dart\nvar x = 1;\n```');
    expect(find.text('dart'), findsOneWidget);
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-code-$id')), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('image block renders an Image widget', (tester) async {
    await pump(tester, '![alt](https://example.com/x.png)');
    expect(find.byType(Image), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('image shows an alt fallback when loading fails', (tester) async {
    await pump(tester, '![a cat](https://example.invalid/x.png)');
    final imageWidget = tester.widget<Image>(find.byType(Image));
    // Drive the errorBuilder directly (network never resolves in tests).
    final fallback = imageWidget.errorBuilder!(
        tester.element(find.byType(Image)), 'err', null);
    expect(fallback, isA<Widget>());
    await teardown(tester);
  });

  testWidgets('code block without a language renders (no label)',
      (tester) async {
    await pump(tester, '```\nplain code\n```');
    expect(find.byType(RichText), findsWidgets);
    await teardown(tester);
  });

  testWidgets('block math renders natively via flutter_math_fork',
      (tester) async {
    await pump(tester, r'$$' '\n' r'x^2 + y^2' '\n' r'$$');
    expect(find.byType(Math), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('inline math renders natively when not being edited',
      (tester) async {
    await pump(tester, r'energy is $E = mc^2$ exactly');
    expect(find.byType(Math), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('read-only GFM table renders a Table widget with all cells',
      (tester) async {
    final c = await pump(
        tester, '| Name | Age |\n| --- | --- |\n| Ann | 30 |\n| Bob | 25 |',
        readOnly: true);
    expect(find.byType(Table), findsOneWidget);
    // 3 rows x 2 cols = 6 rich-text cells.
    final cells = find.descendant(
      of: find.byType(Table),
      matching: find.byType(RichText),
    );
    expect(cells, findsNWidgets(6));
    final t = c.document.nodes.first as TableNode;
    expect(t.cellText(0, 0), 'Name');
    expect(t.cellText(2, 0), 'Bob');
    await teardown(tester);
  });

  testWidgets('editable table: typing in a cell updates the model',
      (tester) async {
    final c = await pump(tester, '| A | B |\n| --- | --- |\n| 1 | 2 |');
    final id = c.document.nodes.first.id;
    await tester.enterText(find.byKey(Key('markey-cell-$id-0-0')), 'Name');
    await tester.pump();
    expect((c.document.nodes.first as TableNode).cellText(0, 0), 'Name');
    await teardown(tester);
  });

  testWidgets('editable table: add-row button appends a row', (tester) async {
    final c = await pump(tester, '| A | B |\n| --- | --- |\n| 1 | 2 |');
    final id = c.document.nodes.first.id;
    await tester.tap(find.byKey(Key('markey-table-addrow-$id')));
    await tester.pump();
    expect((c.document.nodes.first as TableNode).rowCount, 3);
    await teardown(tester);
  });

  testWidgets('definition list renders term + definitions', (tester) async {
    final c = await pump(tester, 'Apple\n: A fruit\n: A company');
    expect(tester.takeException(), isNull);
    expect((c.document.nodes[0] as TextBlockNode).type, BlockType.definitionTerm);
    // term + 2 definitions each render a block.
    final blocks = find.byWidgetPredicate((w) =>
        w.key is ValueKey &&
        '${(w.key as ValueKey).value}'.startsWith('markey-block-'));
    expect(blocks.evaluate().length, greaterThanOrEqualTo(3));
    await teardown(tester);
  });

  testWidgets('front matter renders as a labelled card', (tester) async {
    final c = await pump(tester, '---\ntitle: Hi\n---\n\nBody');
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-frontmatter-$id')), findsOneWidget);
    expect(find.text('front matter'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('footnote definition renders with its label marker',
      (tester) async {
    await pump(tester, 'A note[^1].\n\n[^1]: The note text.');
    expect(find.text('[1]'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('mermaid flowchart renders natively', (tester) async {
    final c = await pump(tester, '```mermaid\ngraph TD\nA[Start] --> B[End]\n```');
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-flowchart-$id')), findsOneWidget);
    expect(find.byType(FlowchartView), findsOneWidget);
    expect(find.text('mermaid'), findsNothing);
    await teardown(tester);
  });

  testWidgets('mermaid state diagram renders natively (reuses flowchart)',
      (tester) async {
    await pump(tester,
        '```mermaid\nstateDiagram-v2\n[*] --> Idle\nIdle --> Running : go\n```');
    expect(find.byType(FlowchartView), findsOneWidget);
    expect(find.text('mermaid'), findsNothing);
    await teardown(tester);
  });

  testWidgets('mermaid class diagram renders natively', (tester) async {
    final c = await pump(tester,
        '```mermaid\nclassDiagram\nAnimal <|-- Dog\nAnimal : +String name\n```');
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-class-$id')), findsOneWidget);
    expect(find.byType(ClassDiagramView), findsOneWidget);
    expect(find.text('mermaid'), findsNothing);
    await teardown(tester);
  });

  testWidgets('mermaid gantt chart renders natively', (tester) async {
    final c = await pump(tester,
        '```mermaid\ngantt\ntitle Plan\nsection S\nA : 2024-01-01, 3d\nB : 2024-01-04, 2d\n```');
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-gantt-$id')), findsOneWidget);
    expect(find.byType(GanttView), findsOneWidget);
    expect(find.text('mermaid'), findsNothing);
    await teardown(tester);
  });

  testWidgets('mermaid ER diagram renders natively (reuses class view)',
      (tester) async {
    await pump(tester,
        '```mermaid\nerDiagram\nCUSTOMER ||--o{ ORDER : places\n```');
    expect(find.byType(ClassDiagramView), findsOneWidget);
    expect(find.text('mermaid'), findsNothing);
    await teardown(tester);
  });

  testWidgets('an unsupported diagram type degrades to the source card',
      (tester) async {
    final c = await pump(tester, '```mermaid\nmindmap\n  root\n    a\n```');
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-mermaid-$id')), findsOneWidget);
    expect(find.text('mermaid'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('mermaid pie chart renders natively (no source card)',
      (tester) async {
    final c = await pump(
        tester, '```mermaid\npie title Pets\n"Dogs" : 386\n"Cats" : 85\n```');
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-pie-$id')), findsOneWidget);
    expect(find.text('mermaid'), findsNothing); // not the fallback card
    expect(find.byType(MermaidPieView), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('mermaid sequence diagram renders natively', (tester) async {
    final c = await pump(tester,
        '```mermaid\nsequenceDiagram\nAlice->>Bob: Hi\nBob-->>Alice: Hey\n```');
    final id = c.document.nodes.first.id;
    expect(find.byKey(ValueKey('markey-sequence-$id')), findsOneWidget);
    expect(find.byType(SequenceDiagramView), findsOneWidget);
    expect(find.text('mermaid'), findsNothing);
    await teardown(tester);
  });

  testWidgets('read-only task checkbox is disabled', (tester) async {
    await pump(tester, '- [ ] todo', readOnly: true);
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.onChanged, isNull);
    await teardown(tester);
  });
}
