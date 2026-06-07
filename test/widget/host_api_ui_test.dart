import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end UI tests for host-facing controller APIs (stats, outline, TOC,
/// HTML export) and the remaining slash-menu commands, driven through a live
/// editor rather than by calling the model directly.
void main() {
  Future<MarkdownEditorController> pumpEditor(
    WidgetTester tester,
    String markdown,
  ) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 600, height: 460, child: MarkdownEditor(controller: c)),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
        find.byKey(ValueKey('markey-block-${c.document.nodes.first.id}')));
    await tester.pump();
    return c;
  }

  Future<void> teardown(WidgetTester tester) async =>
      tester.pumpWidget(const SizedBox());

  group('host APIs reflect content typed through the UI', () {
    testWidgets('a live word-count / outline / TOC status pane updates',
        (tester) async {
      final c = MarkdownEditorController(markdown: '# Title\n\nbody');
      addTearDown(c.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                    height: 360,
                    child: MarkdownEditor(controller: c)),
                // A host-built status pane reading the controller APIs.
                AnimatedBuilder(
                  animation: c,
                  builder: (_, __) {
                    final s = c.documentStats();
                    return Column(children: [
                      Text('words:${s.words}',
                          key: const Key('words')),
                      Text('headings:${c.outline().length}',
                          key: const Key('headings')),
                      Text(c.tableOfContents(), key: const Key('toc')),
                      Text(c.toHtml(), key: const Key('html')),
                    ]);
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Type into the second block (append " more" to "body").
      await tester.tap(
          find.byKey(ValueKey('markey-block-${c.document.nodes.last.id}')));
      await tester.pump();
      c.setSelection(DocumentSelection.collapsed(
          DocumentPosition.text(c.document.nodes.last.id, 4)));
      await tester.pump();
      tester.testTextInput.enterText('body more');
      await tester.pump();

      expect(find.text('words:3'), findsOneWidget); // Title + body + more
      expect(find.text('headings:1'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('toc'))).data,
        '- [Title](#title)',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('html'))).data,
        contains('<h1 id="title">Title</h1>'),
      );
      await teardown(tester);
    });
  });

  group('remaining slash-menu commands convert the block', () {
    Future<void> selectSlash(WidgetTester tester, MarkdownEditorController c,
        String query, String itemId) async {
      tester.testTextInput.enterText('/$query');
      await tester.pump();
      final item = find.byKey(Key('markey_slash_item_$itemId'));
      await tester.ensureVisible(item);
      await tester.pump();
      await tester.tap(item);
      await tester.pump();
    }

    testWidgets('heading 2, heading 3', (tester) async {
      var c = await pumpEditor(tester, '');
      await selectSlash(tester, c, 'head', 'heading2');
      expect((c.document.nodes.first as TextBlockNode).level, 2);
      await teardown(tester);

      c = await pumpEditor(tester, '');
      await selectSlash(tester, c, 'head', 'heading3');
      expect((c.document.nodes.first as TextBlockNode).level, 3);
      await teardown(tester);
    });

    testWidgets('numbered, task and quote', (tester) async {
      var c = await pumpEditor(tester, '');
      await selectSlash(tester, c, 'number', 'numbered');
      expect((c.document.nodes.first as TextBlockNode).type,
          BlockType.numberedListItem);
      await teardown(tester);

      c = await pumpEditor(tester, '');
      await selectSlash(tester, c, 'task', 'task');
      expect((c.document.nodes.first as TextBlockNode).type,
          BlockType.todoListItem);
      await teardown(tester);

      c = await pumpEditor(tester, '');
      await selectSlash(tester, c, 'quote', 'quote');
      expect((c.document.nodes.first as TextBlockNode).type, BlockType.quote);
      await teardown(tester);
    });

    testWidgets('code block', (tester) async {
      final c = await pumpEditor(tester, '');
      await selectSlash(tester, c, 'code', 'code');
      expect(c.document.nodes.any((n) => n is CodeBlockNode), isTrue);
      await teardown(tester);
    });
  });
}
