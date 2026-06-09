import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// The editor must honour the OS font-scale / dynamic-type setting
/// (`MediaQuery.textScaler`), so accessibility font sizes enlarge the rendered
/// text and caret geometry — a hand-painted editor doesn't get this for free.
void main() {
  Future<Size> blockSize(WidgetTester tester, double scale) async {
    final c = MarkdownEditorController(markdown: 'hello world');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 300,
              child: MarkdownEditor(controller: c, enableDrop: false),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final id = c.document.nodes.first.id;
    return tester.getSize(find.byKey(ValueKey('markey-block-$id')));
  }

  testWidgets('text scales up with the OS textScaler', (tester) async {
    final at1 = await blockSize(tester, 1.0);
    final at2 = await blockSize(tester, 2.0);
    // Doubling the text scale roughly doubles the line height.
    expect(at2.height, greaterThan(at1.height * 1.6));
  });

  testWidgets('caret placement honours the scaled layout', (tester) async {
    final c = MarkdownEditorController(markdown: 'hello world');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 300,
              child: MarkdownEditor(controller: c, enableDrop: false),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(MarkdownEditor));
    await tester.pump();
    final id = c.document.nodes.first.id;
    // Tapping near the end of the (scaled) line still lands a sensible caret.
    final box = find.byKey(ValueKey('markey-block-$id'));
    await tester.tapAt(tester.getCenter(box));
    await tester.pump();
    expect(c.selection, isNotNull);
    final off = (c.selection!.extent.nodePosition as TextNodePosition).offset;
    expect(off, inInclusiveRange(0, 'hello world'.length));
  });
}
