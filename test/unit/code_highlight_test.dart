import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/render/code_highlight.dart';

void main() {
  const base = TextStyle(fontSize: 14);
  final hl = const DefaultCodeHighlighter();

  test('produces multiple spans for code with keywords/strings/comments', () {
    final spans = hl.highlight("var x = 'hi'; // note", 'dart', base);
    expect(spans.length, greaterThan(1));
  });

  test('plain text with no tokens yields a single span', () {
    final spans = hl.highlight('plain words here', 'text', base);
    expect(spans.length, 1);
  });

  test('reassembles to the original source (lossless)', () {
    const code = "if (a == 1) return 'x'; // c";
    final spans = hl.highlight(code, 'dart', base);
    final joined =
        spans.map((s) => (s as TextSpan).text ?? '').join();
    expect(joined, code);
  });

  test('null/unknown language still returns spans covering the text', () {
    final spans = hl.highlight('abc', null, base);
    final joined = spans.map((s) => (s as TextSpan).text ?? '').join();
    expect(joined, 'abc');
  });
}
