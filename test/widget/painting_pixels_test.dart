import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Verifies the *painted* layer (CustomPaint/TextPainter) — the part normal
/// widget finders can't see — by rendering to an image and inspecting pixels.
/// Uses distinctive colors so the assertions are robust (no brittle goldens).
void main() {
  // Distinctive, unmistakable colors.
  const selRed = Color(0xFFFF0000);
  const caretBlue = Color(0xFF0000FF);

  // Real glyphs (partial coverage) so selection rects show around the ink;
  // the test font fills the em box and would hide them.
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    var any = false;
    for (final p in const [
      '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    ]) {
      final f = File(p);
      if (f.existsSync()) {
        loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
        any = true;
      }
    }
    if (any) await loader.load();
  });

  EditorStyle style() => EditorStyle.fromTheme(ThemeData.light()).copyWith(
        baseTextStyle: const TextStyle(
            fontFamily: 'Roboto', fontSize: 16, color: Colors.black, height: 1.5),
        selectionColor: selRed,
        caretColor: caretBlue,
      );

  /// Counts pixels matching [c] (with tolerance) in the rendered boundary.
  Future<int> countColor(
    WidgetTester tester,
    Key boundaryKey,
    Color c,
  ) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey));
    int count = 0;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2], a = bytes[i + 3];
        if (a > 40 &&
            (r - ((c.r * 255).round())).abs() < 60 &&
            (g - ((c.g * 255).round())).abs() < 60 &&
            (b - ((c.b * 255).round())).abs() < 60) {
          count++;
        }
      }
      image.dispose();
    });
    return count;
  }

  Future<MarkdownEditorController> pump(
    WidgetTester tester,
    String markdown,
    Key key,
  ) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 400,
              height: 200,
              child: MarkdownEditor(
                controller: c,
                style: style(),
                showToolbar: false,
                enableDrop: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  testWidgets('a selection paints the selection color onto the canvas',
      (tester) async {
    const key = Key('rb');
    final c = await pump(tester, 'hello world', key);

    // No selection → no red.
    expect(await countColor(tester, key, selRed), 0);

    // Select "hello" → red selection rect must be painted.
    await tester.tap(
        find.byKey(ValueKey('markey-block-${c.document.nodes.first.id}')));
    await tester.pump();
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(c.document.nodes.first.id, 0),
      extent: DocumentPosition.text(c.document.nodes.first.id, 5),
    ));
    await tester.pump();
    expect(await countColor(tester, key, selRed), greaterThan(50));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the caret paints the caret color when focused', (tester) async {
    const key = Key('rb2');
    final c = await pump(tester, 'hi', key);
    await tester.tap(
        find.byKey(ValueKey('markey-block-${c.document.nodes.first.id}')));
    await tester.pump();
    c.setSelection(DocumentSelection.collapsed(
        DocumentPosition.text(c.document.nodes.first.id, 2)));
    // Pump to a point where the blink shows the caret.
    await tester.pump(const Duration(milliseconds: 50));
    expect(await countColor(tester, key, caretBlue), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
}
