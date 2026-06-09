import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/render/code_highlight.dart';
import 'package:markey_mark/src/render/code_layout.dart';

/// Direct coverage for [CodeLayout], including the non-incremental fallback used
/// when the highlighter is a plain [CodeHighlighter] (not a [LineHighlighter]).
class _PlainHighlighter implements CodeHighlighter {
  const _PlainHighlighter();
  @override
  List<InlineSpan> highlight(String code, String? language, TextStyle base) =>
      [TextSpan(text: code, style: base)];
}

void main() {
  const base = TextStyle(fontSize: 14, fontFamily: 'monospace');

  testWidgets('fallback (non-line) highlighter splits by line and lays out',
      (tester) async {
    final layout = CodeLayout.build(
      code: 'line one\nsecond line\nthird',
      language: null,
      baseStyle: base,
      highlighter: const _PlainHighlighter(),
      width: 400,
      styleVersion: 1,
    );
    addTearDown(layout.dispose);

    expect(layout.lines.length, 3);
    expect(layout.height, greaterThan(0));
    // Geometry round-trips: a caret offset maps to a point and back.
    final p = layout.getOffsetForCaret(0);
    expect(layout.getPositionForOffset(p), 0);
    // A selection within the first line yields at least one box.
    expect(layout.getBoxesForSelection(0, 4), isNotEmpty);
    // Caret on the second line is below the first.
    final firstLineY = layout.getOffsetForCaret(0).dy;
    final secondLineY = layout.getOffsetForCaret(10).dy;
    expect(secondLineY, greaterThan(firstLineY));
  });

  testWidgets('reuses unchanged line painters across rebuilds (line highlighter)',
      (tester) async {
    final a = CodeLayout.build(
      code: 'aaa\nbbb\nccc',
      language: 'dart',
      baseStyle: base,
      highlighter: const DefaultCodeHighlighter(),
      width: 400,
      styleVersion: 1,
    );
    CodeLayout.debugShapedChars = 0;
    final b = CodeLayout.build(
      code: 'aaa\nbXb\nccc', // only the middle line changed
      language: 'dart',
      baseStyle: base,
      highlighter: const DefaultCodeHighlighter(),
      width: 400,
      styleVersion: 1,
      previous: a,
    );
    addTearDown(b.dispose);
    // Only the changed line re-shaped (the other two were reused).
    expect(CodeLayout.debugShapedChars, lessThan(8));
    expect(b.lines.length, 3);
  });

  testWidgets('empty code yields a single zero-length line', (tester) async {
    final layout = CodeLayout.build(
      code: '',
      language: null,
      baseStyle: base,
      highlighter: const DefaultCodeHighlighter(),
      width: 200,
      styleVersion: 1,
    );
    addTearDown(layout.dispose);
    expect(layout.lines.length, 1);
    expect(layout.getPositionForOffset(const Offset(0, 0)), 0);
  });
}
