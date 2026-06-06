import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

class FakeClipboardBridge implements ClipboardBridge {
  ClipboardPayload? stored;
  @override
  Future<void> write(ClipboardPayload payload) async => stored = payload;
  @override
  Future<ClipboardPayload?> read() async => stored;
}

/// End-to-end UI tests for copy / cut / paste driven via keyboard shortcuts,
/// using an in-memory clipboard bridge (no OS dependency).
void main() {
  Future<MarkdownEditorController> pump(
    WidgetTester tester,
    String markdown,
    ClipboardBridge bridge,
  ) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MarkdownEditor(controller: c, clipboard: bridge),
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

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Ctrl+C copies the selection to the clipboard bridge',
      (tester) async {
    final bridge = FakeClipboardBridge();
    final c = await pump(tester, 'hello world', bridge);
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(id, 0),
      extent: DocumentPosition.text(id, 5),
    ));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyC);
    expect(bridge.stored!.markdown, 'hello');
    await teardown(tester);
  });

  testWidgets('Ctrl+X cuts the selection (copies then removes it)',
      (tester) async {
    final bridge = FakeClipboardBridge();
    final c = await pump(tester, 'hello world', bridge);
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(id, 0),
      extent: DocumentPosition.text(id, 6),
    ));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyX);
    expect(bridge.stored!.markdown, 'hello ');
    expect(c.markdown, 'world');
    await teardown(tester);
  });

  testWidgets('Ctrl+V pastes the clipboard markdown at the caret',
      (tester) async {
    final bridge = FakeClipboardBridge()
      ..stored = const ClipboardPayload(markdown: '**bold**');
    final c = await pump(tester, '', bridge);
    c.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(c.document.nodes.first.id, 0)));
    await tester.pump();
    await press(tester, LogicalKeyboardKey.keyV);
    expect(
      (c.document.nodes.first as TextBlockNode).delta.isFormatted(0, 4, 'bold'),
      isTrue,
    );
    await teardown(tester);
  });
}
