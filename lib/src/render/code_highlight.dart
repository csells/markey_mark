import 'package:flutter/painting.dart';

/// Turns source [code] into styled spans for a code block / source view.
///
/// The contract is **lossless**: concatenating the returned spans' text must
/// reproduce [code] exactly. This is the seam where a richer highlighter
/// (e.g. `re_highlight`) can be plugged in; the built-in default is pure Dart
/// with no dependency, so it works on all platforms with no WebView/JS.
abstract class CodeHighlighter {
  List<InlineSpan> highlight(String code, String? language, TextStyle base);
}

/// A small, native, language-agnostic highlighter covering the universal tokens
/// (line/block comments, strings, numbers, and a broad keyword set). Adjacent
/// unstyled runs are merged so plain text stays a single span.
class DefaultCodeHighlighter implements CodeHighlighter {
  const DefaultCodeHighlighter({
    this.keywordColor = const Color(0xFF0033B3),
    this.stringColor = const Color(0xFF067D17),
    this.numberColor = const Color(0xFF1750EB),
    this.commentColor = const Color(0xFF8C8C8C),
  });

  final Color keywordColor;
  final Color stringColor;
  final Color numberColor;
  final Color commentColor;

  static const Set<String> _keywords = {
    'abstract', 'and', 'as', 'async', 'await', 'bool', 'break', 'case', 'catch',
    'class', 'const', 'continue', 'def', 'default', 'do', 'double', 'dynamic',
    'else', 'enum', 'export', 'extends', 'extension', 'external', 'factory',
    'false', 'final', 'finally', 'float', 'for', 'from', 'function', 'get',
    'if', 'implements', 'import', 'in', 'int', 'interface', 'is', 'let', 'long',
    'mixin', 'new', 'none', 'not', 'null', 'or', 'override', 'package', 'private',
    'protected', 'public', 'return', 'self', 'set', 'static', 'string', 'super',
    'switch', 'this', 'throw', 'true', 'try', 'typedef', 'var', 'void', 'while',
    'with', 'yield',
  };

  static final RegExp _token = RegExp(
    r'(?<comment>//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)'
    "|(?<string>'(?:\\\\.|[^'\\\\])*'|\"(?:\\\\.|[^\"\\\\])*\"|`(?:\\\\.|[^`\\\\])*`)"
    r'|(?<number>\b\d+(?:\.\d+)?\b)'
    r'|(?<word>[A-Za-z_]\w*)',
  );

  @override
  List<InlineSpan> highlight(String code, String? language, TextStyle base) {
    final spans = <TextSpan>[];
    var last = 0;

    void emit(String text, Color? color) {
      if (text.isEmpty) return;
      final style = color == null ? base : base.copyWith(color: color);
      if (spans.isNotEmpty && spans.last.style == style) {
        spans[spans.length - 1] =
            TextSpan(text: (spans.last.text ?? '') + text, style: style);
      } else {
        spans.add(TextSpan(text: text, style: style));
      }
    }

    for (final m in _token.allMatches(code)) {
      if (m.start > last) emit(code.substring(last, m.start), null);
      final text = m.group(0)!;
      Color? color;
      if (m.namedGroup('comment') != null) {
        color = commentColor;
      } else if (m.namedGroup('string') != null) {
        color = stringColor;
      } else if (m.namedGroup('number') != null) {
        color = numberColor;
      } else if (m.namedGroup('word') != null) {
        color = _keywords.contains(text) ? keywordColor : null;
      }
      emit(text, color);
      last = m.end;
    }
    if (last < code.length) emit(code.substring(last), null);
    if (spans.isEmpty) spans.add(TextSpan(text: code, style: base));
    return spans;
  }
}
