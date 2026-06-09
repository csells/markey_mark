import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    await tester.tap(
      find.byKey(ValueKey('markey-block-${c.document.nodes.first.id}')),
    );
    await tester.pump();
    return c;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> ctrlF(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
  }

  String text(MarkdownEditorController c) =>
      (c.document.nodes.first as TextBlockNode).delta.toPlainText();

  testWidgets('Ctrl/Cmd+F opens the find bar', (tester) async {
    await pump(tester, 'find me here');
    expect(find.byKey(const Key('markey_find_bar')), findsNothing);
    await ctrlF(tester);
    expect(find.byKey(const Key('markey_find_bar')), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('typing a query selects the first match', (tester) async {
    final c = await pump(tester, 'a cat and a cat');
    await ctrlF(tester);
    await tester.enterText(find.byKey(const Key('markey_find_field')), 'cat');
    await tester.pump();
    expect(c.selection, isNotNull);
    expect(c.selection!.isCollapsed, isFalse);
    expect((c.selection!.base.nodePosition as TextNodePosition).offset, 2);
    await teardown(tester);
  });

  testWidgets('Replace all replaces every match', (tester) async {
    final c = await pump(tester, 'oo and oo');
    await ctrlF(tester);
    await tester.enterText(find.byKey(const Key('markey_find_field')), 'oo');
    await tester.pump();
    await tester.enterText(
        find.byKey(const Key('markey_find_replace_field')), 'X');
    await tester.pump();
    await tester.tap(find.byKey(const Key('markey_find_replaceall')));
    await tester.pump();
    expect(text(c), 'X and X');
    await teardown(tester);
  });

  testWidgets('the close button hides the find bar', (tester) async {
    await pump(tester, 'text');
    await ctrlF(tester);
    expect(find.byKey(const Key('markey_find_bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('markey_find_close')));
    await tester.pump();
    expect(find.byKey(const Key('markey_find_bar')), findsNothing);
    await teardown(tester);
  });
}
