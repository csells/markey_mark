import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

class FakeClipboardBridge implements ClipboardBridge {
  ClipboardPayload? stored;
  @override
  Future<void> write(ClipboardPayload payload) async => stored = payload;
  @override
  Future<ClipboardPayload?> read() async => stored;
}

/// End-to-end UI tests for the native right-click / long-press context menu
/// (AdaptiveTextSelectionToolbar): copy, cut, paste, select all.
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
    return c;
  }

  Future<void> teardown(WidgetTester tester) async =>
      tester.pumpWidget(const SizedBox());

  Offset blockCenter(WidgetTester tester, MarkdownEditorController c) =>
      tester.getCenter(
          find.byKey(ValueKey('markey-block-${c.document.nodes.first.id}')));

  testWidgets('right-click opens a menu with Paste and Select all',
      (tester) async {
    final c = await pump(tester, 'hello world', FakeClipboardBridge());
    await tester.tapAt(blockCenter(tester, c), buttons: kSecondaryButton);
    await tester.pump();
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);
    await teardown(tester);
  });

  testWidgets('Select all in the menu selects the whole document',
      (tester) async {
    final c = await pump(tester, 'one\n\ntwo', FakeClipboardBridge());
    await tester.tapAt(blockCenter(tester, c), buttons: kSecondaryButton);
    await tester.pump();
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(c.selection!.base.nodeId, c.document.nodes.first.id);
    expect(c.selection!.extent.nodeId, c.document.nodes.last.id);
    await teardown(tester);
  });

  testWidgets('Copy appears for a selection and copies to the bridge',
      (tester) async {
    final bridge = FakeClipboardBridge();
    final c = await pump(tester, 'hello world', bridge);
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(id, 0),
      extent: DocumentPosition.text(id, 5),
    ));
    await tester.pump();
    await tester.tapAt(blockCenter(tester, c), buttons: kSecondaryButton);
    await tester.pump();
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    await tester.pump();
    expect(bridge.stored!.markdown, 'hello');
    await teardown(tester);
  });

  testWidgets('Paste in the menu inserts the clipboard content',
      (tester) async {
    final bridge = FakeClipboardBridge()
      ..stored = const ClipboardPayload(markdown: '**bold**');
    final c = await pump(tester, '', bridge);
    c.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(c.document.nodes.first.id, 0)));
    await tester.pump();
    await tester.tapAt(blockCenter(tester, c), buttons: kSecondaryButton);
    await tester.pump();
    await tester.tap(find.text('Paste'));
    await tester.pump();
    await tester.pump();
    expect(
      (c.document.nodes.first as TextBlockNode).delta.isFormatted(0, 4, 'bold'),
      isTrue,
    );
    await teardown(tester);
  });

  testWidgets('read-only editors only offer Copy / Select all', (tester) async {
    final c = await pump(tester, 'text', FakeClipboardBridge());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MarkdownEditor(controller: c, readOnly: true),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tapAt(blockCenter(tester, c), buttons: kSecondaryButton);
    await tester.pump();
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Cut'), findsNothing);
    await teardown(tester);
  });

  testWidgets('Escape dismisses the context menu', (tester) async {
    final c = await pump(tester, 'hello world', FakeClipboardBridge());
    await tester.tapAt(blockCenter(tester, c), buttons: kSecondaryButton);
    await tester.pump();
    expect(find.text('Paste'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Paste'), findsNothing);
    await teardown(tester);
  });

  testWidgets('tapping elsewhere dismisses the context menu', (tester) async {
    final c = await pump(tester, 'hello world', FakeClipboardBridge());
    await tester.tapAt(blockCenter(tester, c), buttons: kSecondaryButton);
    await tester.pump();
    expect(find.text('Paste'), findsOneWidget);
    await tester.tapAt(const Offset(30, 380)); // primary tap in empty editor space
    await tester.pump();
    expect(find.text('Paste'), findsNothing);
    await teardown(tester);
  });

  testWidgets('source field sets a visible selection color', (tester) async {
    final c = await pump(tester, '# Title', FakeClipboardBridge());
    c.toggleMode(); // WYSIWYG -> source
    await tester.pump();
    final field = find.byKey(const Key('markey_source_field'));
    expect(field, findsOneWidget);
    // Before the fix the source TextField had no TextSelectionTheme ancestor,
    // so the selection was invisible against the highlighted source.
    final selTheme = tester
        .widgetList<TextSelectionTheme>(
          find.ancestor(of: field, matching: find.byType(TextSelectionTheme)),
        )
        .first;
    expect(selTheme.data.selectionColor, isNotNull);
    await teardown(tester);
  });

  testWidgets('web: editor mounts/unmounts cleanly with context-menu suppression',
      (tester) async {
    // On web the editor calls BrowserContextMenu.disableContextMenu() in
    // initState and re-enables it on dispose. Assert that builds and tears down
    // without throwing on the web target. (The actual suppression is a global
    // browser effect, verified in a real browser — it isn't observable through
    // flutter_test's mocked platform channel, so we don't assert on it here.)
    await pump(tester, 'hi', FakeClipboardBridge());
    expect(find.byType(MarkdownEditor), findsOneWidget);
    await teardown(tester);
    expect(find.byType(MarkdownEditor), findsNothing);
  });
}
