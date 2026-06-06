import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end UI tests for cross-block selection: selecting, deleting and
/// replacing text that spans multiple blocks — driven through the real widget.
void main() {
  Future<MarkdownEditorController> pump(
    WidgetTester tester,
    String markdown,
  ) async {
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

  testWidgets('Ctrl/Cmd+A selects the whole document', (tester) async {
    final c = await pump(tester, 'one\n\ntwo\n\nthree');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();

    final sel = c.selection!;
    expect(sel.base.nodeId, c.document.nodes.first.id);
    expect(sel.extent.nodeId, c.document.nodes.last.id);
    expect((sel.extent.nodePosition as TextNodePosition).offset, 5); // 'three'
    await teardown(tester);
  });

  testWidgets('select-all then Backspace clears the document', (tester) async {
    final c = await pump(tester, 'one\n\ntwo\n\nthree');
    c.selectAll();
    await tester.pump();
    // Simulate the IME deleting the (cross-block) selection.
    tester.testTextInput.enterText('');
    await tester.pump();
    expect(c.document.length, 1);
    expect((c.document.nodes.first as TextBlockNode).delta.toPlainText(), '');
    await teardown(tester);
  });

  testWidgets('select-all then typing replaces the whole document',
      (tester) async {
    final c = await pump(tester, 'one\n\ntwo\n\nthree');
    c.selectAll();
    await tester.pump();
    tester.testTextInput.enterText('Z');
    await tester.pump();
    expect(c.document.length, 1);
    expect((c.document.nodes.first as TextBlockNode).delta.toPlainText(), 'Z');
    await teardown(tester);
  });

  testWidgets('shift+click extends the selection across blocks',
      (tester) async {
    final c = await pump(tester, 'hello\n\nworld');
    final firstId = c.document.nodes.first.id;
    final lastId = c.document.nodes.last.id;

    // Click to place the caret in the first block.
    await tester.tapAt(
        tester.getTopLeft(find.byKey(ValueKey('markey-block-$firstId'))) +
            const Offset(4, 6));
    await tester.pump();
    expect(c.selection!.base.nodeId, firstId);

    // Shift+click in the last block extends the selection there.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.tapAt(
        tester.getCenter(find.byKey(ValueKey('markey-block-$lastId'))));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    final sel = c.selection!;
    expect(sel.base.nodeId, firstId);
    expect(sel.extent.nodeId, lastId);
    expect(sel.isCollapsed, isFalse);
    await teardown(tester);
  });
}
