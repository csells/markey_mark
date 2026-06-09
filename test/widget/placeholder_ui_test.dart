import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  Future<MarkdownEditorController> pump(
    WidgetTester tester,
    String markdown, {
    String? placeholder,
  }) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MarkdownEditor(controller: c, placeholder: placeholder),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  testWidgets('shows the placeholder for an empty document', (tester) async {
    await pump(tester, '', placeholder: 'Start writing…');
    expect(find.text('Start writing…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hides the placeholder once there is content', (tester) async {
    final c = await pump(tester, '', placeholder: 'Start writing…');
    await tester.tap(
        find.byKey(ValueKey('markey-block-${c.document.nodes.first.id}')));
    await tester.pump();
    tester.testTextInput.enterText('hi');
    await tester.pump();
    expect(find.text('Start writing…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no placeholder when the document already has content',
      (tester) async {
    await pump(tester, 'hello', placeholder: 'Start writing…');
    expect(find.text('Start writing…'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no placeholder widget when none is configured', (tester) async {
    await pump(tester, '');
    // Nothing to assert beyond a clean build with no placeholder text.
    expect(find.byKey(const Key('markey_placeholder')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
