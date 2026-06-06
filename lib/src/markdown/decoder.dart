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
        encodeHtml: false,
      );

  Document convert(String markdown) {
    final mdNodes = _newMdDocument().parse(markdown);
    final nodes = <Node>[];
    for (final mdNode in mdNodes) {
      final block = _mapBlock(mdNode);
      if (block != null) nodes.add(block);
    }
    return Document(nodes);
  }

  Node? _mapBlock(md.Node node) {
    if (node is md.Text) {
      // Stray text at block level → paragraph.
      final text = node.text.trim();
      if (text.isEmpty) return null;
      return TextBlockNode.paragraph(delta: Delta.text(text));
    }
    if (node is! md.Element) return null;

    final tag = node.tag;
    if (tag.length == 2 && tag[0] == 'h') {
      final level = int.tryParse(tag[1]);
      if (level != null && level >= 1 && level <= 6) {
        return TextBlockNode.heading(level: level, delta: _mapInline(node.children));
      }
    }
    switch (tag) {
      case 'p':
        return TextBlockNode.paragraph(delta: _mapInline(node.children));
      default:
        // Fallback: keep content as a paragraph rather than dropping it.
        return TextBlockNode.paragraph(delta: _mapInline(node.children));
    }
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
