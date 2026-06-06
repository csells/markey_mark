import 'package:markdown/markdown.dart' as md;

import '../model/attributes.dart';
import '../model/delta.dart';
import '../model/document.dart';
import '../model/node.dart';

/// Parses Markdown text into a [Document] using `dart-lang/markdown` for
/// tokenizing and our own AST→model mapping.
///
/// Vertical slice coverage: paragraphs, ATX headings (1–6), and the inline
/// marks bold/italic/strikethrough/inline-code/links. Unknown block types fall
/// back to a paragraph carrying their inline content so nothing is lost.
class MarkdownDecoder {
  MarkdownDecoder();

  md.Document _newMdDocument() => md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        blockSyntaxes: [MathBlockSyntax()],
        inlineSyntaxes: [MathInlineSyntax()],
        encodeHtml: false,
      );

  Document convert(String markdown) {
    final mdNodes = _newMdDocument().parse(markdown);
    final nodes = <Node>[];
    for (final mdNode in mdNodes) {
      nodes.addAll(_expand(mdNode));
    }
    return Document(nodes);
  }

  List<Node> _expand(md.Node node) {
    if (node is md.Text) {
      final text = node.text.trim();
      if (text.isEmpty) return const [];
      return [TextBlockNode.paragraph(delta: Delta.text(text))];
    }
    if (node is! md.Element) return const [];

    final tag = node.tag;
    if (tag.length == 2 && tag[0] == 'h') {
      final level = int.tryParse(tag[1]);
      if (level != null && level >= 1 && level <= 6) {
        return [TextBlockNode.heading(level: level, delta: _mapInline(node.children))];
      }
    }
    switch (tag) {
      case 'p':
        final image = _soleImage(node);
        if (image != null) return [image];
        return [TextBlockNode.paragraph(delta: _mapInline(node.children))];
      case 'img':
        return [_imageOf(node)];
      case 'hr':
        return [HorizontalRuleNode()];
      case 'ul':
        return _listItems(node, ordered: false);
      case 'ol':
        return _listItems(node, ordered: true);
      case 'blockquote':
        return _quote(node);
      case 'math_block':
        return [MathBlockNode(tex: node.textContent)];
      case 'table':
        return [_table(node)];
      case 'section':
        if ((node.attributes['class'] ?? '').contains('footnotes')) {
          return _footnoteDefs(node);
        }
        return [TextBlockNode.paragraph(delta: _mapInline(node.children))];
      case 'pre':
        return [_codeOrMermaid(node)];
      case 'code':
        // Bare code element treated as a code block.
        return [_codeOrMermaid(node)];
      default:
        return [TextBlockNode.paragraph(delta: _mapInline(node.children))];
    }
  }

  /// Inline children of a list item / quote, flattening wrapping `<p>` and
  /// skipping nested lists (handled as their own blocks later).
  List<md.Node> _inlineChildren(md.Element element) {
    final out = <md.Node>[];
    for (final c in element.children ?? const <md.Node>[]) {
      if (c is md.Element && (c.tag == 'ul' || c.tag == 'ol')) continue;
      if (c is md.Element && c.tag == 'p') {
        out.addAll(c.children ?? const <md.Node>[]);
      } else {
        out.add(c);
      }
    }
    return out;
  }

  List<Node> _listItems(md.Element list, {required bool ordered}) {
    final start = int.tryParse(list.attributes['start'] ?? '1') ?? 1;
    final out = <Node>[];
    var index = 0;
    for (final li in list.children ?? const <md.Node>[]) {
      if (li is! md.Element || li.tag != 'li') continue;
      final inlineNodes = _inlineChildren(li);
      final checked = _checkboxState(inlineNodes);
      var delta = _mapInline(inlineNodes);

      // Task-list checkbox: GFM renders it as an <input> element (no text);
      // text-prefix is a fallback if the checkbox wasn't parsed.
      if (checked != null) {
        delta = _trimLeadingSpace(delta);
        out.add(TextBlockNode.todo(checked: checked, delta: delta));
      } else {
        final plain = delta.toPlainText();
        if (plain.startsWith('[ ] ')) {
          out.add(TextBlockNode.todo(
              checked: false, delta: delta.slice(4, delta.length)));
        } else if (plain.startsWith('[x] ') || plain.startsWith('[X] ')) {
          out.add(TextBlockNode.todo(
              checked: true, delta: delta.slice(4, delta.length)));
        } else if (ordered) {
          out.add(TextBlockNode.numbered(number: start + index, delta: delta));
        } else {
          out.add(TextBlockNode.bullet(delta: delta));
        }
      }
      index++;
    }
    return out;
  }

  /// Returns the checked state if [nodes] contain a task-list checkbox
  /// `<input type="checkbox">`, else null.
  bool? _checkboxState(List<md.Node> nodes) {
    for (final n in nodes) {
      if (n is md.Element && n.tag == 'input') {
        return n.attributes.containsKey('checked');
      }
    }
    return null;
  }

  Delta _trimLeadingSpace(Delta delta) {
    final plain = delta.toPlainText();
    if (plain.startsWith(' ')) return delta.slice(1, delta.length);
    return delta;
  }

  List<Node> _quote(md.Element quote) {
    final out = <Node>[];
    for (final child in quote.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'p') {
        out.add(TextBlockNode.quote(delta: _mapInline(child.children)));
      } else if (child is md.Element && child.tag == 'blockquote') {
        out.addAll(_quote(child)); // nested → flattened for now
      } else if (child is md.Text && child.text.trim().isNotEmpty) {
        out.add(TextBlockNode.quote(delta: Delta.text(child.text.trim())));
      }
    }
    if (out.isEmpty) {
      out.add(TextBlockNode.quote(delta: _mapInline(quote.children)));
    }
    return out;
  }

  /// If [p] contains only a single image (ignoring whitespace), returns it.
  ImageNode? _soleImage(md.Element p) {
    md.Element? img;
    for (final c in p.children ?? const <md.Node>[]) {
      if (c is md.Element && c.tag == 'img') {
        if (img != null) return null; // more than one image
        img = c;
      } else if (c is md.Text && c.text.trim().isEmpty) {
        continue;
      } else {
        return null; // other content present
      }
    }
    return img == null ? null : _imageOf(img);
  }

  ImageNode _imageOf(md.Element img) => ImageNode(
        url: img.attributes['src'] ?? '',
        alt: (img.attributes['alt'] ?? '').isEmpty ? null : img.attributes['alt'],
        title: img.attributes['title'],
      );

  List<Node> _footnoteDefs(md.Element section) {
    final out = <Node>[];
    void visitList(md.Element ol) {
      for (final li in ol.children ?? const <md.Node>[]) {
        if (li is! md.Element || li.tag != 'li') continue;
        final label = li.footnoteLabel ??
            (li.attributes['id'] ?? '').replaceFirst('fn-', '');
        // Inline content of the definition, minus the back-reference link.
        final inline = <md.Node>[];
        for (final child in li.children ?? const <md.Node>[]) {
          if (child is md.Element && child.tag == 'p') {
            inline.addAll(child.children ?? const <md.Node>[]);
          } else {
            inline.add(child);
          }
        }
        inline.removeWhere((n) =>
            n is md.Element &&
            n.tag == 'a' &&
            (n.attributes['class'] ?? '').contains('footnote-backref'));
        final delta = _trimTrailingSpace(_mapInline(inline));
        out.add(TextBlockNode.footnoteDef(label: label, delta: delta));
      }
    }

    for (final child in section.children ?? const <md.Node>[]) {
      if (child is md.Element && child.tag == 'ol') visitList(child);
    }
    return out;
  }

  Delta _trimTrailingSpace(Delta delta) {
    final plain = delta.toPlainText();
    final trimmed = plain.replaceFirst(RegExp(r'\s+$'), '');
    if (trimmed.length == plain.length) return delta;
    return delta.slice(0, trimmed.length);
  }

  TableNode _table(md.Element table) {
    final rows = <List<Delta>>[];
    final alignments = <TableAlign>[];

    void addRow(md.Element tr, {required bool header}) {
      final cells = <Delta>[];
      for (final cell in tr.children ?? const <md.Node>[]) {
        if (cell is! md.Element) continue;
        if (cell.tag != 'th' && cell.tag != 'td') continue;
        cells.add(_mapInline(cell.children));
        if (header) alignments.add(_alignOf(cell));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }

    for (final section in table.children ?? const <md.Node>[]) {
      if (section is! md.Element) continue;
      if (section.tag == 'thead') {
        for (final tr in section.children ?? const <md.Node>[]) {
          if (tr is md.Element && tr.tag == 'tr') addRow(tr, header: true);
        }
      } else if (section.tag == 'tbody') {
        for (final tr in section.children ?? const <md.Node>[]) {
          if (tr is md.Element && tr.tag == 'tr') addRow(tr, header: false);
        }
      } else if (section.tag == 'tr') {
        addRow(section, header: rows.isEmpty);
      }
    }
    return TableNode(rows: rows, alignments: alignments);
  }

  TableAlign _alignOf(md.Element cell) {
    switch (cell.attributes['align']) {
      case 'left':
        return TableAlign.left;
      case 'center':
        return TableAlign.center;
      case 'right':
        return TableAlign.right;
      default:
        return TableAlign.none;
    }
  }

  /// A fenced code block, or a [MermaidNode] when the language is `mermaid`.
  Node _codeOrMermaid(md.Element pre) {
    final code = _codeBlock(pre);
    if (code.language == 'mermaid') {
      return MermaidNode(source: code.code);
    }
    return code;
  }

  CodeBlockNode _codeBlock(md.Element pre) {
    md.Element? codeEl;
    if (pre.tag == 'code') {
      codeEl = pre;
    } else {
      for (final c in pre.children ?? const <md.Node>[]) {
        if (c is md.Element && c.tag == 'code') {
          codeEl = c;
          break;
        }
      }
    }
    final el = codeEl ?? pre;
    var code = el.textContent;
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    String? language;
    final cls = el.attributes['class'];
    if (cls != null && cls.startsWith('language-')) {
      language = cls.substring('language-'.length);
    }
    return CodeBlockNode(code: code, language: language);
  }

  Delta _mapInline(List<md.Node>? children) {
    if (children == null || children.isEmpty) return Delta.empty();
    final visitor = _InlineMapper();
    for (final child in children) {
      child.accept(visitor);
    }
    return visitor.delta.normalized;
  }
}

/// Walks an inline AST subtree with an attribute stack, emitting [Delta] runs
/// (the appflowy `DeltaMarkdownDecoder` pattern).
class _InlineMapper implements md.NodeVisitor {
  final List<Attributes> _stack = [const {}];
  final List<TextRun> _runs = [];

  Delta get delta => Delta(_runs);

  Attributes get _current {
    final merged = <String, Object?>{};
    for (final frame in _stack) {
      merged.addAll(frame);
    }
    return merged;
  }

  @override
  bool visitElementBefore(md.Element element) {
    switch (element.tag) {
      case 'strong':
        _stack.add(const {InlineAttr.bold: true});
      case 'em':
        _stack.add(const {InlineAttr.italic: true});
      case 'del':
        _stack.add(const {InlineAttr.strike: true});
      case 'code':
        _stack.add(const {InlineAttr.code: true});
        // Inline code content is a Text child; emit it directly and skip.
        final content = element.textContent;
        _runs.add(TextRun(content, _current));
        _stack.removeLast();
        return false;
      case 'a':
        final href = element.attributes['href'] ?? '';
        _stack.add({InlineAttr.link: href});
      case 'math':
        _runs.add(TextRun(element.textContent, {InlineAttr.math: true}));
        _stack.add(const {});
        return false;
      case 'sup':
        if ((element.attributes['class'] ?? '').contains('footnote-ref')) {
          final label = element.textContent;
          _runs.add(TextRun(label, {InlineAttr.footnote: label}));
          _stack.add(const {});
          return false; // don't descend into the ref's anchor
        }
        _stack.add(const {});
      default:
        _stack.add(const {});
    }
    return true;
  }

  @override
  void visitText(md.Text text) {
    _runs.add(TextRun(text.text, _current));
  }

  @override
  void visitElementAfter(md.Element element) {
    if (element.tag == 'code') return; // already popped
    if (_stack.length > 1) _stack.removeLast();
  }
}

/// A custom block syntax for display math fences: `$$` … `$$` on their own
/// lines, producing a `math_block` element whose text is the LaTeX source.
class MathBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^\s*\$\$\s*$');

  @override
  md.Node? parse(md.BlockParser parser) {
    final lines = <String>[];
    parser.advance(); // consume the opening `$$`
    while (!parser.isDone) {
      if (pattern.hasMatch(parser.current.content)) {
        parser.advance(); // consume the closing `$$`
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }
    return md.Element.text('math_block', lines.join('\n'));
  }
}

/// A custom inline syntax for `$...$` math, producing a `math` element whose
/// text is the LaTeX source. (Block `$$ … $$` is handled by [MathBlockSyntax].)
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'\$([^$\n]+)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math', match[1]!));
    return true;
  }
}
