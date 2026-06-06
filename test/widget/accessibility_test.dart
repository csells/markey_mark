import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  Future<MarkdownEditorController> pump(
      WidgetTester tester, String markdown) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MarkdownEditor(controller: c),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  testWidgets('headings expose header semantics with their text',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, '# Big Title\n\nBody text here.');

    expect(find.bySemanticsLabel('Big Title'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Big Title'));
    expect(node.flagsCollection.isHeader, isTrue);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paragraphs expose their text as a semantics label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, 'A plain paragraph.');
    expect(find.bySemanticsLabel('A plain paragraph.'), findsOneWidget);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('images expose their alt text as an image semantics label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, '![A friendly cat](https://example.com/cat.png)');
    final node = tester.getSemantics(find.bySemanticsLabel('A friendly cat'));
    expect(node.flagsCollection.isImage, isTrue);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
