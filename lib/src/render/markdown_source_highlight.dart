import 'package:flutter/painting.dart';

/// Colors for Markdown source highlighting (source mode).
class MarkdownSourceTheme {
  const MarkdownSourceTheme({
    this.markerColor = const Color(0xFF0033B3),
    this.codeColor = const Color(0xFF067D17),
    this.linkColor = const Color(0xFF1750EB),
  });
  final Color markerColor;
  final Color codeColor;
  final Color linkColor;
}

final RegExp _md = RegExp(
  r'(?<h>^#{1,6} )'
  r'|(?<li>^\s*(?:[-*+]|\d+[.)]) )'
  r'|(?<q>^> )'
  r'|(?<fence>^```[^\n]*)'
  r'|(?<bold>\*\*[^*\n]+\*\*|__[^_\n]+__)'
  r'|(?<code>`[^`\n]+`)'
  r'|(?<italic>\*[^*\n]+\*|_[^_\n]+_)'
  r'|(?<link>\[[^\]\n]*\]\([^)\n]*\))',
  multiLine: true,
);

/// Tokenizes Markdown [source] into styled spans for the raw-source editor.
///
/// Lossless: concatenating the spans' text reproduces [source]. Pure Dart, no
/// dependency — the native answer to a CodeMirror-style source view.
List<TextSpan> markdownSourceSpans(
  String source,
  TextStyle base, {
  MarkdownSourceTheme theme = const MarkdownSourceTheme(),
}) {
  final spans = <TextSpan>[];
  var last = 0;

  void emit(String text, TextStyle style) {
    if (text.isEmpty) return;
    if (spans.isNotEmpty && spans.last.style == style) {
      spans[spans.length - 1] =
          TextSpan(text: (spans.last.text ?? '') + text, style: style);
    } else {
      spans.add(TextSpan(text: text, style: style));
    }
  }

  for (final m in _md.allMatches(source)) {
    if (m.start > last) emit(source.substring(last, m.start), base);
    final text = m.group(0)!;
    TextStyle style;
    if (m.namedGroup('h') != null ||
        m.namedGroup('li') != null ||
        m.namedGroup('q') != null) {
      style = base.copyWith(color: theme.markerColor, fontWeight: FontWeight.bold);
    } else if (m.namedGroup('fence') != null || m.namedGroup('code') != null) {
      style = base.copyWith(color: theme.codeColor);
    } else if (m.namedGroup('bold') != null) {
      style = base.copyWith(fontWeight: FontWeight.bold);
    } else if (m.namedGroup('italic') != null) {
      style = base.copyWith(fontStyle: FontStyle.italic);
    } else if (m.namedGroup('link') != null) {
      style = base.copyWith(color: theme.linkColor);
    } else {
      style = base;
    }
    emit(text, style);
    last = m.end;
  }
  if (last < source.length) emit(source.substring(last), base);
  if (spans.isEmpty) spans.add(TextSpan(text: source, style: base));
  return spans;
}
