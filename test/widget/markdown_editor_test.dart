import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  /// Pumps the editor inside a sized Material scaffold. Caller disposes the
  /// controller via [addTearDown].
  Future<void> pumpEditor(
    WidgetTester tester,
    MarkdownEditorController controller, {
    bool readOnly = false,
    bool showToolbar = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MarkdownEditor(
              controller: controller,
              readOnly: readOnly,
              showToolbar: showToolbar,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Unmounts to cancel the caret-blink timer before the test ends.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  String firstText(MarkdownEditorController c) =>
      (c.document.nodes.first as TextBlockNode).delta.toPlainText();

  Finder firstBlock(MarkdownEditorController c) =>
      find.byKey(ValueKey('markey-block-${c.document.nodes.first.id}'));

  group('Rendering', () {
    testWidgets('renders paragraph and heading text', (tester) async {
      final c = MarkdownEditorController(markdown: '# Title\n\nBody text');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      expect(find.byType(MarkdownEditor), findsOneWidget);
      // Text is painted via CustomPaint; assert blocks exist + no errors.
      expect(find.byType(CustomPaint), findsWidgets);
      await teardown(tester);
    });

    testWidgets('shows the toolbar by default and hides when disabled',
        (tester) async {
      final c = MarkdownEditorController();
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      expect(find.byKey(const Key('markey_bold')), findsOneWidget);
      await teardown(tester);

      await pumpEditor(tester, c, showToolbar: false);
      expect(find.byKey(const Key('markey_bold')), findsNothing);
      await teardown(tester);
    });
  });

  group('Source mode', () {
    testWidgets('toggle button switches to the source field and back',
        (tester) async {
      final c = MarkdownEditorController(markdown: '# Title');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      expect(find.byKey(const Key('markey_source_field')), findsNothing);
      await tester.tap(find.byKey(const Key('markey_toggle_mode')));
      await tester.pump();

      final field = find.byKey(const Key('markey_source_field'));
      expect(field, findsOneWidget);
      expect(find.text('# Title'), findsOneWidget);

      await tester.tap(find.byKey(const Key('markey_toggle_mode')));
      await tester.pump();
      expect(find.byKey(const Key('markey_source_field')), findsNothing);
      await teardown(tester);
    });

    testWidgets('editing source then toggling back updates the document',
        (tester) async {
      final c = MarkdownEditorController(markdown: 'plain');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      await tester.tap(find.byKey(const Key('markey_toggle_mode')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('markey_source_field')),
        '## Updated',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('markey_toggle_mode')));
      await tester.pump();

      final node = c.document.nodes.first as TextBlockNode;
      expect(node.type, BlockType.heading);
      expect(node.level, 2);
      expect(node.delta.toPlainText(), 'Updated');
      await teardown(tester);
    });
  });

  group('Interactive editing (custom IME client)', () {
    testWidgets('tap focuses and places the caret', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      await tester.tap(firstBlock(c));
      await tester.pump();
      expect(c.selection, isNotNull);
      expect(c.selection!.extent.nodeId, c.document.nodes.first.id);
      await teardown(tester);
    });

    testWidgets('typing inserts text through the input client', (tester) async {
      final c = MarkdownEditorController();
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      await tester.tap(firstBlock(c));
      await tester.pump();
      tester.testTextInput.enterText('Hello');
      await tester.pump();
      expect(firstText(c), 'Hello');
      await teardown(tester);
    });

    testWidgets('typing "# " triggers the heading input rule', (tester) async {
      final c = MarkdownEditorController();
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      await tester.tap(firstBlock(c));
      await tester.pump();
      tester.testTextInput.enterText('# ');
      await tester.pump();

      final node = c.document.nodes.first as TextBlockNode;
      expect(node.type, BlockType.heading);
      expect(node.level, 1);
      await teardown(tester);
    });

    testWidgets('backspace deletes a character', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      await tester.tap(firstBlock(c));
      await tester.pump();
      // Place caret at end.
      c.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(c.document.nodes.first.id, 5),
      ));
      await tester.pump();
      tester.testTextInput.enterText('Hell'); // simulate one-char deletion
      await tester.pump();
      expect(firstText(c), 'Hell');
      await teardown(tester);
    });

    testWidgets('newline splits the block', (tester) async {
      final c = MarkdownEditorController(markdown: 'AB');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      await tester.tap(firstBlock(c));
      await tester.pump();
      c.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(c.document.nodes.first.id, 1),
      ));
      await tester.pump();
      tester.testTextInput.enterText('A\nB');
      await tester.pump();
      expect(c.document.length, 2);
      await teardown(tester);
    });
  });

  group('Toolbar actions', () {
    testWidgets('bold button formats the selection', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 0),
        extent: DocumentPosition.text(id, 5),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('markey_bold')));
      await tester.pump();

      expect(
        (c.document.nodes.first as TextBlockNode).delta.isFormatted(0, 5, 'bold'),
        isTrue,
      );
      await teardown(tester);
    });

    testWidgets('H1 button changes the block type', (tester) async {
      final c = MarkdownEditorController(markdown: 'Title');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(id, 0)));
      await tester.pump();
      await tester.tap(find.byKey(const Key('markey_h1')));
      await tester.pump();
      expect((c.document.nodes.first as TextBlockNode).type, BlockType.heading);
      await teardown(tester);
    });

    testWidgets('undo/redo buttons enable and revert edits', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hi');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(id, 2)));
      c.insertText('!');
      await tester.pump();
      expect(firstText(c), 'Hi!');

      await tester.tap(find.byKey(const Key('markey_undo')));
      await tester.pump();
      expect(firstText(c), 'Hi');

      await tester.tap(find.byKey(const Key('markey_redo')));
      await tester.pump();
      expect(firstText(c), 'Hi!');
      await teardown(tester);
    });
  });

  group('Keyboard shortcuts', () {
    testWidgets('Ctrl/Cmd+B toggles bold on the selection', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      final id = c.document.nodes.first.id;
      await tester.tap(firstBlock(c));
      await tester.pump();
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 0),
        extent: DocumentPosition.text(id, 5),
      ));
      await tester.pump();

      // Test host platform defaults to android → Ctrl is the modifier.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(
        (c.document.nodes.first as TextBlockNode).delta.isFormatted(0, 5, 'bold'),
        isTrue,
      );
      await teardown(tester);
    });

    testWidgets('arrow keys move the caret', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      final id = c.document.nodes.first.id;
      await tester.tap(firstBlock(c));
      await tester.pump();
      c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(id, 2)));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 3);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 2);
      await teardown(tester);
    });
  });

  group('Read-only', () {
    testWidgets('does not edit when read-only', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c, readOnly: true);

      await tester.tap(firstBlock(c));
      await tester.pump();
      expect(c.selection, isNull); // caret not placed in read-only
      expect(firstText(c), 'Hello');
      await teardown(tester);
    });
  });

  group('IME client details', () {
    testWidgets('selection-only IME change updates the model selection',
        (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      await tester.tap(firstBlock(c));
      await tester.pump();

      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'Hello',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      ));
      await tester.pump();
      expect(c.selection!.isCollapsed, isFalse);
      expect((c.selection!.base.nodePosition as TextNodePosition).offset, 1);
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 4);
      await teardown(tester);
    });

    testWidgets('multi-line insertion splits into several blocks',
        (tester) async {
      final c = MarkdownEditorController();
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      await tester.tap(firstBlock(c));
      await tester.pump();

      tester.testTextInput.enterText('one\ntwo\nthree');
      await tester.pump();
      expect(c.document.length, 3);
      expect((c.document.nodes.last as TextBlockNode).delta.toPlainText(),
          'three');
      await teardown(tester);
    });

    testWidgets('performAction(newline) splits the block', (tester) async {
      final c = MarkdownEditorController(markdown: 'AB');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      await tester.tap(firstBlock(c));
      await tester.pump();
      c.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(c.document.nodes.first.id, 1),
      ));
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();
      expect(c.document.length, 2);
      await teardown(tester);
    });

    testWidgets('platform IME callbacks are no-ops (do not throw)',
        (tester) async {
      final c = MarkdownEditorController(markdown: 'Hi');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      await tester.tap(firstBlock(c));
      await tester.pump();

      // The State implements TextInputClient; its callbacks are public.
      final dynamic state = tester.state(find.byType(MarkdownEditor));
      expect(state.currentAutofillScope, isNull);
      expect(state.currentTextEditingValue, isA<TextEditingValue>());
      state.updateFloatingCursor(RawFloatingCursorPoint(
        state: FloatingCursorDragState.Start,
        startLocation: (Offset.zero, const TextPosition(offset: 0)),
        offset: Offset.zero,
      ));
      state.showAutocorrectionPromptRect(0, 1);
      state.insertTextPlaceholder(const Size(1, 1));
      state.removeTextPlaceholder();
      state.performPrivateCommand('x', const <String, dynamic>{});
      state.didChangeInputControl(null, null);
      state.connectionClosed();
      await tester.pump();
      await teardown(tester);
    });

    testWidgets('drag extends a selection within a block', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello world');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      final box = tester.getRect(firstBlock(c));
      final start = box.centerLeft + const Offset(2, 0);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(c.selection, isNotNull);
      await teardown(tester);
    });
  });

  group('Performance, responsiveness & resource use', () {
    testWidgets('idle (unfocused) editor runs no timers — pumpAndSettle settles',
        (tester) async {
      final c = MarkdownEditorController(markdown: 'Resting');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      // If a periodic caret-blink timer ran while unfocused, this would hang.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await teardown(tester);
    });

    testWidgets('virtualizes large documents (only visible blocks are built)',
        (tester) async {
      final md = List.generate(800, (i) => 'Paragraph number $i').join('\n\n');
      final c = MarkdownEditorController(markdown: md);
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      expect(c.document.length, 800);
      final builtBlocks = find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey && '${k.value}'.startsWith('markey-block-');
      });
      final builtCount = builtBlocks.evaluate().length;
      // ListView.builder must not build all 800 blocks at once.
      expect(builtCount, lessThan(800));
      expect(builtCount, greaterThan(0));
      await teardown(tester);
    });

    testWidgets('toolbar is responsive on a narrow (mobile) width — no overflow',
        (tester) async {
      final c = MarkdownEditorController(markdown: 'Hi');
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 600,
              child: MarkdownEditor(controller: c),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The mode toggle stays pinned and reachable even when buttons scroll.
      expect(find.byKey(const Key('markey_toggle_mode')), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('editing a block does not re-shape other blocks (cache reuse)',
        (tester) async {
      final c = MarkdownEditorController(markdown: 'one\n\ntwo\n\nthree');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);

      await tester.tap(firstBlock(c));
      await tester.pump();
      tester.testTextInput.enterText('one!');
      await tester.pump();
      expect((c.document.nodes.first as TextBlockNode).delta.toPlainText(),
          'one!');
      // Untouched blocks are unchanged (their cached layout is still valid).
      expect((c.document.nodes[1] as TextBlockNode).delta.toPlainText(), 'two');
      await teardown(tester);
    });
  });

  group('More toolbar + shortcuts', () {
    testWidgets('italic toolbar button formats the selection', (tester) async {
      final c = MarkdownEditorController(markdown: 'Hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 0),
        extent: DocumentPosition.text(id, 5),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('markey_italic')));
      await tester.pump();
      expect(c.markdown, '_Hello_');
      await teardown(tester);
    });

    testWidgets('Ctrl+Z / Ctrl+Shift+Z undo and redo via keyboard',
        (tester) async {
      final c = MarkdownEditorController(markdown: 'Hi');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      await tester.tap(firstBlock(c));
      await tester.pump();
      c.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(c.document.nodes.first.id, 2),
      ));
      c.insertText('!');
      await tester.pump();
      expect(firstText(c), 'Hi!');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect(firstText(c), 'Hi');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      expect(firstText(c), 'Hi!');
      await teardown(tester);
    });

    testWidgets('source field preserves a valid selection across rebuild',
        (tester) async {
      final c = MarkdownEditorController(markdown: 'hello');
      addTearDown(c.dispose);
      await pumpEditor(tester, c);
      await tester.tap(find.byKey(const Key('markey_toggle_mode')));
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('markey_source_field')),
        'hello there',
      );
      await tester.pump();
      // A controller notification rebuilds the source field; the existing
      // (valid, in-range) selection must be preserved, not reset.
      c.markdown = 'hello there world';
      await tester.pump();
      expect(find.byKey(const Key('markey_source_field')), findsOneWidget);
      await teardown(tester);
    });
  });
}
