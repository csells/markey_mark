import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// RTL / bidi rendering: paragraphs whose first strong character is RTL
/// (Arabic/Hebrew) lay out and align right-to-left, while LTR paragraphs stay
/// LTR — per-paragraph base direction, so a mixed document renders each block
/// correctly. (Flutter's TextPainter handles intra-line bidi once it knows the
/// base direction.)
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
            height: 300,
            child: MarkdownEditor(controller: c, enableDrop: false),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  TextDirection blockDirection(WidgetTester tester, String id) {
    final dir = tester.widget<Directionality>(
      find.ancestor(
        of: find.byKey(ValueKey('markey-block-$id')),
        matching: find.byType(Directionality),
      ).first,
    );
    return dir.textDirection;
  }

  testWidgets('an Arabic paragraph lays out right-to-left', (tester) async {
    final c = await pump(tester, 'مرحبا بالعالم');
    expect(blockDirection(tester, c.document.nodes.first.id), TextDirection.rtl);
  });

  testWidgets('a Hebrew paragraph lays out right-to-left', (tester) async {
    final c = await pump(tester, 'שלום עולם');
    expect(blockDirection(tester, c.document.nodes.first.id), TextDirection.rtl);
  });

  testWidgets('an English paragraph stays left-to-right', (tester) async {
    final c = await pump(tester, 'hello world');
    expect(blockDirection(tester, c.document.nodes.first.id), TextDirection.ltr);
  });

  testWidgets('each block keeps its own base direction in a mixed document',
      (tester) async {
    final c = await pump(tester, 'hello\n\nمرحبا');
    expect(blockDirection(tester, c.document.nodes[0].id), TextDirection.ltr);
    expect(blockDirection(tester, c.document.nodes[1].id), TextDirection.rtl);
  });

  testWidgets('caret/selection still work in RTL text (logical offsets)',
      (tester) async {
    final c = await pump(tester, 'שלום עולם');
    final id = c.document.nodes.first.id;
    await tester.tap(find.byType(MarkdownEditor));
    await tester.pump();
    // Logical caret movement is unchanged by direction: place at start, move
    // right one grapheme → logical offset 1.
    c.placeCaretAt(DocumentPosition.text(id, 0));
    c.moveCaretRight();
    expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 1);
  });
}
