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

  testWidgets('read-only task checkbox is disabled', (tester) async {
    await pump(tester, '- [ ] todo', readOnly: true);
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.onChanged, isNull);
    await teardown(tester);
  });
}
