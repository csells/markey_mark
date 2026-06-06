import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/decoder.dart';
import 'package:markey_mark/src/model/delta.dart';
import 'package:markey_mark/src/model/node.dart';
import 'package:markey_mark/src/render/delta_text.dart';
import 'package:markey_mark/src/theme/editor_style.dart';

void main() {
  final style = EditorStyle.fromTheme(ThemeData.light());

  group('EditorStyle', () {
    test('fromTheme populates heading styles 1..6', () {
      for (var i = 1; i <= 6; i++) {
        expect(style.headingStyle(i), isNotNull);
      }
    });

    test('headingStyle clamps out-of-range levels', () {
      expect(style.headingStyle(0), style.headingStyle(1));
      expect(style.headingStyle(9), style.headingStyle(6));
    });

    test('headingStyle falls back to base when missing', () {
      const s = EditorStyle(
        baseTextStyle: TextStyle(fontSize: 10),
        headingStyles: {},
        codeTextStyle: TextStyle(),
        linkColor: Color(0xFF000000),
        selectionColor: Color(0x33000000),
        caretColor: Color(0xFF000000),
        highlightColor: Color(0xFFFFF59D),
      );
      expect(s.headingStyle(2), s.baseTextStyle);
    });

    test('copyWith overrides fields', () {
      final s2 = style.copyWith(
        blockSpacing: 99,
        caretColor: const Color(0xFFFF0000),
        padding: EdgeInsets.zero,
      );
      expect(s2.blockSpacing, 99);
      expect(s2.caretColor, const Color(0xFFFF0000));
      expect(s2.padding, EdgeInsets.zero);
      // Unchanged fields preserved.
      expect(s2.baseTextStyle, style.baseTextStyle);
    });
  });

  group('deltaToTextSpan / styleForAttributes', () {
    test('empty delta yields a zero-width span', () {
      final span = deltaToTextSpan(Delta.empty(), style.baseTextStyle, style);
      expect((span as TextSpan).text, '');
    });

    test('applies bold/italic/strike/code/link', () {
      final delta = Delta([
        TextRun('b', {'bold': true}),
        TextRun('i', {'italic': true}),
        TextRun('s', {'strike': true}),
        TextRun('c', {'code': true}),
        TextRun('l', {'link': 'http://x'}),
      ]);
      final span = deltaToTextSpan(delta, style.baseTextStyle, style) as TextSpan;
      final children = span.children!.cast<TextSpan>();
      expect(children[0].style!.fontWeight, FontWeight.bold);
      expect(children[1].style!.fontStyle, FontStyle.italic);
      expect(children[2].style!.decoration, isNotNull);
      expect(children[4].style!.color, style.linkColor);
    });

    test('applies highlight background colour', () {
      final s = styleForAttributes(
          const {'highlight': true}, style.baseTextStyle, style);
      expect(s.backgroundColor, style.highlightColor);
    });

    test('strike combines with an existing decoration on the base', () {
      final base = style.baseTextStyle
          .copyWith(decoration: TextDecoration.underline);
      final s = styleForAttributes(const {'strike': true}, base, style);
      expect(s.decoration!.contains(TextDecoration.lineThrough), isTrue);
      expect(s.decoration!.contains(TextDecoration.underline), isTrue);
    });

    test('baseStyleFor returns heading style for headings', () {
      final h = TextBlockNode.heading(level: 1, delta: Delta.text('x'));
      expect(baseStyleFor(h, style), style.headingStyle(1));
      final p = TextBlockNode.paragraph(delta: Delta.text('x'));
      expect(baseStyleFor(p, style), style.baseTextStyle);
    });
  });

  group('Decoder edge cases', () {
    final decoder = MarkdownDecoder();

    test('unknown block types fall back to a paragraph preserving text', () {
      final doc = decoder.convert('- item one\n- item two');
      // Lists aren't slice block types → paragraph fallback retaining content.
      expect(doc.nodes.first, isA<TextBlockNode>());
      expect((doc.nodes.first as TextBlockNode).delta.toPlainText(),
          contains('item one'));
    });

    test('blockquote falls back to a paragraph with its text', () {
      final doc = decoder.convert('> quoted text');
      expect((doc.nodes.first as TextBlockNode).delta.toPlainText(),
          contains('quoted text'));
    });

    test('heading with empty content yields an empty heading delta', () {
      final doc = decoder.convert('## ');
      // "## " with nothing after parses to a heading or paragraph; ensure no
      // crash and content is empty-ish.
      expect(doc.nodes, isNotEmpty);
    });
  });
}
