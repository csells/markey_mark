import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end UI tests: every input rule is exercised by typing through the
/// real widget's text-input client (not by calling the model directly), per the
/// rule that a feature isn't done until it works from the UI.
void main() {
  Future<MarkdownEditorController> pump(WidgetTester tester) async {
    final c = MarkdownEditorController();
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

  TextBlockNode first(MarkdownEditorController c) =>
      c.document.nodes.first as TextBlockNode;

  group('Block input rules (typed via UI)', () {
    testWidgets('"- " makes a bullet (shows • marker)', (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('- ');
      await tester.pump();
      expect(first(c).type, BlockType.bulletedListItem);
      expect(find.text('•'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('"1. " makes a numbered item (shows 1. marker)', (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('1. ');
      await tester.pump();
      expect(first(c).type, BlockType.numberedListItem);
      expect(find.text('1.'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('"[] " makes a task item (shows a checkbox)', (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('[] ');
      await tester.pump();
      expect(first(c).type, BlockType.todoListItem);
      expect(find.byType(Checkbox), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('"> " makes a quote (shows the quote bar)', (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('> ');
      await tester.pump();
      expect(first(c).type, BlockType.quote);
      expect(find.byKey(ValueKey('markey-quote-${c.document.nodes.first.id}')),
          findsOneWidget);
      await teardown(tester);
    });

    testWidgets('"---" makes a horizontal rule (shows a Divider)',
        (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('---');
      await tester.pump();
      expect(c.document.nodes.first, isA<HorizontalRuleNode>());
      expect(find.byType(Divider), findsOneWidget);
      await teardown(tester);
    });
  });

  group('Inline input rules (typed via UI)', () {
    testWidgets('**bold**', (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('**b**');
      await tester.pump();
      expect(first(c).delta.runs.single.attributes, {'bold': true});
      await teardown(tester);
    });

    testWidgets('_italic_', (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('_i_');
      await tester.pump();
      expect(first(c).delta.runs.single.attributes, {'italic': true});
      await teardown(tester);
    });

    testWidgets('~~strike~~', (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('~~s~~');
      await tester.pump();
      expect(first(c).delta.runs.single.attributes, {'strike': true});
      await teardown(tester);
    });

    testWidgets('`code`', (tester) async {
      final c = await pump(tester);
      tester.testTextInput.enterText('`c`');
      await tester.pump();
      expect(first(c).delta.runs.single.attributes, {'code': true});
      await teardown(tester);
    });
  });
}
