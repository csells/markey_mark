import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Native PDF export: the document renders to a valid PDF byte stream with no
/// WebView/JS and no third-party dependency (a pure-Dart writer using the
/// built-in PDF base fonts).
void main() {
  String asLatin1(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

  test('produces a structurally valid PDF with the document text', () {
    final doc = Markdown.parse('# Title\n\nA paragraph of body text.');
    final bytes = Markdown.toPdf(doc);
    final s = asLatin1(bytes);

    expect(s.startsWith('%PDF-1.'), isTrue);
    expect(s.trimRight().endsWith('%%EOF'), isTrue);
    expect(s, contains('/Type /Catalog'));
    expect(s, contains('/Type /Pages'));
    expect(s, contains('startxref'));
    expect(s, contains('xref'));
    // The visible text appears in a content stream.
    expect(s, contains('Title'));
    expect(s, contains('A paragraph of body text.'));
  });

  test('escapes PDF string metacharacters', () {
    final doc = Markdown.parse(r'Text with (parens) and a backslash \ here');
    final s = asLatin1(Markdown.toPdf(doc));
    // ( ) and \ are backslash-escaped inside the PDF string.
    expect(s, contains(r'\(parens\)'));
    expect(s, contains(r'and a backslash \\ here'));
  });

  test('paginates long documents into multiple page objects', () {
    final long = List.generate(200, (i) => 'Paragraph number $i.').join('\n\n');
    final s = asLatin1(Markdown.toPdf(Markdown.parse(long)));
    final pageCount = '/Type /Page'.allMatches(s).length -
        '/Type /Pages'.allMatches(s).length; // exclude the Pages tree node
    expect(pageCount, greaterThan(1));
  });

  test('empty document still yields a valid one-page PDF', () {
    final s = asLatin1(Markdown.toPdf(Document.empty()));
    expect(s.startsWith('%PDF-1.'), isTrue);
    expect(s, contains('/Type /Page'));
    expect(s.trimRight().endsWith('%%EOF'), isTrue);
  });
}
