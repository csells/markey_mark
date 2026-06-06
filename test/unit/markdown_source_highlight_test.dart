import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/render/markdown_source_highlight.dart';

void main() {
  const base = TextStyle(fontSize: 14);

  String join(List<TextSpan> spans) =>
      spans.map((s) => s.text ?? '').join();

  test('highlights heading markers and inline marks (multiple spans)', () {
    final spans = markdownSourceSpans('# Title with **bold**', base);
    expect(spans.length, greaterThan(1));
  });

  test('is lossless (spans rejoin to the source)', () {
    const src = '# H\n\n- item with `code` and _em_\n\n> quote';
    final spans = markdownSourceSpans(src, base);
    expect(join(spans), src);
  });

  test('plain text with no markup is a single span', () {
    final spans = markdownSourceSpans('just some words', base);
    expect(spans.length, 1);
  });

  test('bold marker run is styled bold', () {
    final spans = markdownSourceSpans('a **b** c', base);
    final boldSpan = spans.firstWhere((s) => s.text == '**b**');
    expect(boldSpan.style!.fontWeight, FontWeight.bold);
  });

  test('highlight run is styled with a background colour', () {
    final spans = markdownSourceSpans('a ==hot== b', base);
    final span = spans.firstWhere((s) => s.text == '==hot==');
    expect(span.style!.backgroundColor, isNotNull);
  });

  test('callout marker line is styled like a marker and is lossless', () {
    const src = '> [!NOTE]\n> body';
    final spans = markdownSourceSpans(src, base);
    expect(join(spans), src);
    expect(spans.any((s) => (s.text ?? '').contains('[!NOTE]')), isTrue);
  });
}
