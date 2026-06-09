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

  group('line-based stateful tokenizing', () {
    Color? colorAt(List<TextSpan> spans, int charIndex) {
      var i = 0;
      for (final s in spans) {
        final t = s.text ?? '';
        if (charIndex < i + t.length) return s.style?.color;
        i += t.length;
      }
      return null;
    }

    test('highlightLine is lossless and carries no state for plain text', () {
      final r = hl.highlightLine('let value = 42', 0, 'js', base);
      expect(r.spans.map((s) => s.text).join(), 'let value = 42');
      expect(r.endState, 0);
    });

    test('an unterminated block comment carries state to the next line', () {
      final r1 = hl.highlightLine('code /* start', 0, 'c', base);
      expect(r1.endState, isNot(0)); // inside a block comment now
      // The text after /* is comment-coloured.
      expect(colorAt(r1.spans, r1.spans.map((s) => s.text!).join().indexOf('/*')),
          hl.commentColor);

      // Continuing in that state: the whole middle line is a comment.
      final r2 = hl.highlightLine('still inside', r1.endState, 'c', base);
      expect(r2.endState, r1.endState);
      expect(r2.spans.length, 1);
      expect(r2.spans.first.style?.color, hl.commentColor);

      // The closing line returns to the normal state.
      final r3 = hl.highlightLine('done */ x = 1', r2.endState, 'c', base);
      expect(r3.endState, 0);
      expect(r3.spans.map((s) => s.text).join(), 'done */ x = 1');
    });

    test('whole-block highlight folds the line tokenizer (multi-line comment)',
        () {
      const code = 'a = 1\n/* big\n   block */\nb = 2';
      final spans = hl.highlight(code, 'c', base).cast<TextSpan>();
      expect(spans.map((s) => s.text ?? '').join(), code);
      // The interior of the block comment (the second line's text) is coloured
      // as a comment even though it has no comment markers itself.
      final flat = spans.map((s) => s.text ?? '').join();
      expect(colorAt(spans, flat.indexOf('big')), hl.commentColor);
      expect(colorAt(spans, flat.indexOf('block')), hl.commentColor);
    });
  });
}
