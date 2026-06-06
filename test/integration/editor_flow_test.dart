import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end flows exercising the whole stack (widget → controller → editor →
/// commands/input-rules → model → markdown) the way a user would.
void main() {
  Future<MarkdownEditorController> pump(
    WidgetTester tester, {
    String? markdown,
  }) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 500,
            child: MarkdownEditor(controller: c),
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

  Finder block(MarkdownEditorController c, int i) =>
      find.byKey(ValueKey('markey-block-${c.document.nodes[i].id}'));

  testWidgets('author a document from scratch, then inspect Markdown',
      (tester) async {
    final c = await pump(tester);

    // Focus the first (empty) block.
    await tester.tap(block(c, 0));
    await tester.pump();

    // Type a heading using the live "# " input rule.
    tester.testTextInput.enterText('# ');
    await tester.pump();
    tester.testTextInput.enterText('My Title');
    await tester.pump();

    expect((c.document.nodes.first as TextBlockNode).type, BlockType.heading);
    expect(c.markdown, '# My Title');

    // New paragraph via Enter (newline), then body text.
    final headingId = c.document.nodes.first.id;
    c.setSelection(DocumentSelection.collapsed(
      DocumentPosition.text(headingId, 'My Title'.length),
    ));
    await tester.pump();
    tester.testTextInput.enterText('My Title\n');
    await tester.pump();
    expect(c.document.length, 2);

    final bodyId = c.document.nodes[1].id;
    c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(bodyId, 0)));
    await tester.pump();
    tester.testTextInput.enterText('Hello world');
    await tester.pump();

    expect(c.markdown, '# My Title\n\nHello world');
    await teardown(tester);
  });

  testWidgets('bold via toolbar is reflected in Markdown and is undoable',
      (tester) async {
    final c = await pump(tester, markdown: 'make me bold');
    final id = c.document.nodes.first.id;

    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(id, 8),
      extent: DocumentPosition.text(id, 12),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('markey_bold')));
    await tester.pump();

    expect(c.markdown, 'make me **bold**');

    await tester.tap(find.byKey(const Key('markey_undo')));
    await tester.pump();
    expect(c.markdown, 'make me bold');
    await teardown(tester);
  });

  testWidgets('round-trips through source mode without data loss',
      (tester) async {
    final c = await pump(tester, markdown: '# Title\n\nWith **bold** and _italic_.');

    // Switch to source, confirm the raw markdown is shown.
    await tester.tap(find.byKey(const Key('markey_toggle_mode')));
    await tester.pump();
    expect(find.text('# Title\n\nWith **bold** and _italic_.'), findsOneWidget);

    // Edit the source and switch back.
    await tester.enterText(
      find.byKey(const Key('markey_source_field')),
      '# Changed\n\nNow _only italic_.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('markey_toggle_mode')));
    await tester.pump();

    expect(c.document.length, 2);
    expect((c.document.nodes.first as TextBlockNode).delta.toPlainText(),
        'Changed');
    expect(c.markdown, '# Changed\n\nNow _only italic_.');
    await teardown(tester);
  });

  testWidgets('full markdown fidelity survives a wysiwyg→source→wysiwyg trip',
      (tester) async {
    const source =
        '# Heading\n\nParagraph with **bold**, _italic_, ~~strike~~, `code` '
        'and a [link](https://example.com).';
    final c = await pump(tester, markdown: source);

    await tester.tap(find.byKey(const Key('markey_toggle_mode')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('markey_toggle_mode')));
    await tester.pump();

    expect(c.markdown, source);
    await teardown(tester);
  });

  testWidgets('rich blocks round-trip through the source toggle in the UI',
      (tester) async {
    const source = '# Title\n\n'
        '- one\n- two\n\n'
        '1. first\n2. second\n\n'
        '- [ ] todo\n- [x] done\n\n'
        '> a quote\n\n'
        '```dart\nvar x = 1;\n```\n\n'
        r'$$' '\n' r'E = mc^2' '\n' r'$$' '\n\n'
        '![pic](https://example.com/p.png)\n\n'
        '---';
    final c = await pump(tester, markdown: source);

    await tester.tap(find.byKey(const Key('markey_toggle_mode')));
    await tester.pump();
    expect(find.text(source), findsOneWidget);

    await tester.tap(find.byKey(const Key('markey_toggle_mode')));
    await tester.pump();
    expect(c.markdown, source);
    await teardown(tester);
  });
}
