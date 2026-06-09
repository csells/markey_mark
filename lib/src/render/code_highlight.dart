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

/// The result of tokenizing a single line: its styled [spans] plus the
/// [endState] to carry into the next line (for multi-line constructs).
class LineHighlight {
  const LineHighlight(this.spans, this.endState);
  final List<TextSpan> spans;
  final int endState;
}

/// A highlighter that can tokenize one line at a time, carrying a small integer
/// state between lines. This lets a per-line layout (see `CodeLayout`) re-run
/// highlighting only for changed lines and forward until the carried state
/// stabilizes — O(changed lines), not O(block) — exactly how CodeMirror
/// tokenizes incrementally. State `0` always means "normal" (line start).
abstract class LineHighlighter {
  LineHighlight highlightLine(
      String line, int startState, String? language, TextStyle base);
}

/// A small, native, language-agnostic highlighter covering the universal tokens
/// (line/block comments, strings, numbers, and a broad keyword set). Adjacent
/// unstyled runs are merged so plain text stays a single span.
///
/// Tokenizing is **line-based and stateful** ([highlightLine]); the whole-block
/// [highlight] is a fold of the line tokenizer over the lines, so the two can
/// never diverge and multi-line block comments still colour correctly.
class DefaultCodeHighlighter implements CodeHighlighter, LineHighlighter {
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

  /// Carried state: not inside any multi-line construct.
  static const int _normal = 0;

  /// Carried state: inside an unterminated `/* … */` block comment.
  static const int _inBlockComment = 1;

  static const int _slash = 0x2f; // /
  static const int _star = 0x2a; // *
  static const int _hash = 0x23; // #
  static const int _backslash = 0x5c; // \
  static const int _squote = 0x27; // '
  static const int _dquote = 0x22; // "
  static const int _backtick = 0x60; // `

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

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
  static bool _isWordStart(int c) =>
      c == 0x5f || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
  static bool _isWordChar(int c) => _isWordStart(c) || _isDigit(c);

  @override
  List<InlineSpan> highlight(String code, String? language, TextStyle base) {
    final lines = code.split('\n');
    final spans = <TextSpan>[];
    var state = _normal;

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

    for (var k = 0; k < lines.length; k++) {
      if (k > 0) {
        // The line separator itself is comment-coloured while inside a block
        // comment (so a multi-line `/* … */` is uniformly coloured), else plain.
        emit('\n', state == _inBlockComment ? commentColor : null);
      }
      final lh = highlightLine(lines[k], state, language, base);
      for (final s in lh.spans) {
        emit(s.text ?? '', s.style?.color);
      }
      state = lh.endState;
    }
    if (spans.isEmpty) spans.add(TextSpan(text: code, style: base));
    return spans;
  }

  @override
  LineHighlight highlightLine(
      String line, int startState, String? language, TextStyle base) {
    final spans = <TextSpan>[];
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

    final n = line.length;
    var i = 0;
    var state = startState;
    var plainStart = 0;
    void flushPlain(int end) {
      if (end > plainStart) emit(line.substring(plainStart, end), null);
    }

    // Continue an open block comment from the previous line.
    if (state == _inBlockComment) {
      final close = line.indexOf('*/');
      if (close < 0) {
        emit(line, commentColor);
        return LineHighlight(spans, _inBlockComment);
      }
      emit(line.substring(0, close + 2), commentColor);
      i = close + 2;
      plainStart = i;
      state = _normal;
    }

    while (i < n) {
      final c = line.codeUnitAt(i);

      // Block comment open `/* … */` (may run to end of line → carry state).
      if (c == _slash && i + 1 < n && line.codeUnitAt(i + 1) == _star) {
        flushPlain(i);
        final close = line.indexOf('*/', i + 2);
        if (close < 0) {
          emit(line.substring(i), commentColor);
          i = n;
          plainStart = n;
          state = _inBlockComment;
          break;
        }
        emit(line.substring(i, close + 2), commentColor);
        i = close + 2;
        plainStart = i;
        continue;
      }

      // Line comments: `//…` and `#…` run to end of line.
      if ((c == _slash && i + 1 < n && line.codeUnitAt(i + 1) == _slash) ||
          c == _hash) {
        flushPlain(i);
        emit(line.substring(i), commentColor);
        i = n;
        plainStart = n;
        break;
      }

      // Strings: '…' "…" `…` (line-local; closes at the matching unescaped
      // quote or end of line).
      if (c == _squote || c == _dquote || c == _backtick) {
        flushPlain(i);
        var j = i + 1;
        while (j < n) {
          final cj = line.codeUnitAt(j);
          if (cj == _backslash) {
            j += 2;
            continue;
          }
          if (cj == c) {
            j++;
            break;
          }
          j++;
        }
        if (j > n) j = n;
        emit(line.substring(i, j), stringColor);
        i = j;
        plainStart = i;
        continue;
      }

      // Numbers: \b\d+(\.\d+)?\b — not adjacent to word characters.
      if (_isDigit(c) && (i == 0 || !_isWordChar(line.codeUnitAt(i - 1)))) {
        var j = i + 1;
        while (j < n && _isDigit(line.codeUnitAt(j))) {
          j++;
        }
        if (j + 1 < n &&
            line.codeUnitAt(j) == 0x2e &&
            _isDigit(line.codeUnitAt(j + 1))) {
          j += 2;
          while (j < n && _isDigit(line.codeUnitAt(j))) {
            j++;
          }
        }
        if (j >= n || !_isWordChar(line.codeUnitAt(j))) {
          flushPlain(i);
          emit(line.substring(i, j), numberColor);
          i = j;
          plainStart = i;
          continue;
        }
      }

      // Words / keywords.
      if (_isWordStart(c)) {
        var j = i + 1;
        while (j < n && _isWordChar(line.codeUnitAt(j))) {
          j++;
        }
        final word = line.substring(i, j);
        flushPlain(i);
        emit(word, _keywords.contains(word) ? keywordColor : null);
        i = j;
        plainStart = i;
        continue;
      }

      i++;
    }
    flushPlain(i);
    return LineHighlight(spans, state);
  }
}
