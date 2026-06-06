import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  Future<MarkdownEditorController> pump(WidgetTester tester) async {
    final c = MarkdownEditorController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 460,
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

  TextBlockNode first(MarkdownEditorController c) =>
      c.document.nodes.first as TextBlockNode;

  testWidgets('typing "/" opens the slash menu', (tester) async {
    await pump(tester);
    tester.testTextInput.enterText('/');
    await tester.pump();
    expect(find.byKey(const Key('markey_slash_menu')), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('the menu filters as you type a query', (tester) async {
    await pump(tester);
    tester.testTextInput.enterText('/head');
    await tester.pump();
    expect(find.text('Heading 1'), findsOneWidget);
    expect(find.text('Quote'), findsNothing);
    await teardown(tester);
  });

  testWidgets('selecting an item converts the block and clears the query',
      (tester) async {
    final c = await pump(tester);
    tester.testTextInput.enterText('/');
    await tester.pump();
    await tester.tap(find.byKey(const Key('markey_slash_item_heading1')));
    await tester.pump();

    final node = first(c);
    expect(node.type, BlockType.heading);
    expect(node.level, 1);
    expect(node.delta.toPlainText(), '');
    expect(find.byKey(const Key('markey_slash_menu')), findsNothing);
    await teardown(tester);
  });

  testWidgets('selecting "Divider" inserts a horizontal rule', (tester) async {
    final c = await pump(tester);
    tester.testTextInput.enterText('/');
    await tester.pump();
    final divider = find.byKey(const Key('markey_slash_item_divider'));
    await tester.ensureVisible(divider);
    await tester.pump();
    await tester.tap(divider);
    await tester.pump();
    expect(c.document.nodes.any((n) => n is HorizontalRuleNode), isTrue);
    await teardown(tester);
  });

  testWidgets('a non-matching query shows no items', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SlashMenu(
          items: defaultSlashItems,
          query: 'zzzznomatch',
          onSelected: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(ListTile), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Escape dismisses the menu', (tester) async {
    await pump(tester);
    tester.testTextInput.enterText('/');
    await tester.pump();
    expect(find.byKey(const Key('markey_slash_menu')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('markey_slash_menu')), findsNothing);
    await teardown(tester);
  });
}
