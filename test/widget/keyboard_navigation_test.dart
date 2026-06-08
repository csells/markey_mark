import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// UI tests for the unified caret/selection motor wired to the keyboard:
/// vertical movement with a preserved goal column, word/line/document moves,
/// and shift-to-extend — the things a custom (non-EditableText) editor must
/// reimplement, modelled on Flutter's `DefaultTextEditingShortcuts` and
/// super_editor's per-component orchestration. The test font is fixed-width, so
/// column arithmetic is deterministic.
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
            child: MarkdownEditor(controller: c, enableDrop: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(MarkdownEditor));
    await tester.pump();
    return c;
  }

  int off(MarkdownEditorController c) =>
      (c.selection!.extent.nodePosition as TextNodePosition).offset;
  String node(MarkdownEditorController c) => c.selection!.extent.nodeId;

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k,
      {bool shift = false, bool control = false, bool alt = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.alt);
    await tester.sendKeyEvent(k);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.alt);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
  }

  group('vertical movement', () {
    testWidgets('ArrowDown/Up moves between blocks preserving the column',
        (tester) async {
      final c = await pump(tester, 'aaaa bbbb\n\ncccc dddd');
      final a = c.document.nodes[0].id;
      final b = c.document.nodes[1].id;
      c.placeCaretAt(DocumentPosition.text(a, 5));
      await tester.pump();

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(node(c), b);
      expect(off(c), 5); // same column

      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(node(c), a);
      expect(off(c), 5);
    });

    testWidgets('the goal column survives passing through a short line',
        (tester) async {
      // Long, short, long: a down through the short block must remember col 7.
      final c = await pump(tester, 'aaaaaaaa\n\nbb\n\ncccccccc');
      final a = c.document.nodes[0].id;
      final b = c.document.nodes[1].id;
      final cc = c.document.nodes[2].id;
      c.placeCaretAt(DocumentPosition.text(a, 7));
      await tester.pump();

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(node(c), b);
      expect(off(c), 2); // clamped to the short line's end

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(node(c), cc);
      expect(off(c), 7); // goal column restored, not stuck at 2
    });

    testWidgets('Shift+ArrowDown extends the selection across blocks',
        (tester) async {
      final c = await pump(tester, 'aaaa\n\nbbbb');
      final a = c.document.nodes[0].id;
      final b = c.document.nodes[1].id;
      c.placeCaretAt(DocumentPosition.text(a, 2));
      await tester.pump();

      await key(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(c.selection!.base.nodeId, a); // anchor kept
      expect((c.selection!.base.nodePosition as TextNodePosition).offset, 2);
      expect(node(c), b); // extent moved down
      expect(c.selection!.isCollapsed, isFalse);
    });

    testWidgets('vertical movement works inside a multi-line code block',
        (tester) async {
      final c = await pump(tester, '```\nline1\nline2\n```');
      final id = c.document.nodes.first.id;
      c.placeCaretAt(DocumentPosition.text(id, 2)); // "li|ne1"
      await tester.pump();

      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(node(c), id); // stayed in the code block
      expect(off(c), 8); // "line1\nli|ne2" → col 2 of second line (6 + 2)
    });
  });

  group('word / line / document movement', () {
    testWidgets('Ctrl+ArrowRight moves by word', (tester) async {
      final c = await pump(tester, 'foo bar baz');
      final id = c.document.nodes.first.id;
      c.placeCaretAt(DocumentPosition.text(id, 0));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.arrowRight, control: true);
      expect(off(c), 3); // end of "foo"
    });

    testWidgets('Home/End move to the line boundary', (tester) async {
      final c = await pump(tester, 'hello world');
      final id = c.document.nodes.first.id;
      c.placeCaretAt(DocumentPosition.text(id, 5));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.home);
      expect(off(c), 0);
      await key(tester, LogicalKeyboardKey.end);
      expect(off(c), 11);
    });

    testWidgets('Ctrl+End jumps to the end of the document', (tester) async {
      final c = await pump(tester, 'first\n\nsecond');
      final last = c.document.nodes[1].id;
      c.placeCaretAt(DocumentPosition.text(c.document.nodes[0].id, 0));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.end, control: true);
      expect(node(c), last);
      expect(off(c), 6);
    });

    testWidgets('Shift+End extends the selection to the line end',
        (tester) async {
      final c = await pump(tester, 'hello world');
      final id = c.document.nodes.first.id;
      c.placeCaretAt(DocumentPosition.text(id, 0));
      await tester.pump();
      await key(tester, LogicalKeyboardKey.end, shift: true);
      expect(c.selection!.isCollapsed, isFalse);
      expect((c.selection!.base.nodePosition as TextNodePosition).offset, 0);
      expect(off(c), 11);
    });
  });

}
