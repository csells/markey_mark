import '../model/attributes.dart';
import '../model/delta.dart';
import '../model/document.dart';
import '../model/node.dart';

/// Serializes a [Document] to Markdown text.
///
/// We own this (the `markdown` package ships no serializer). The inline encoder
/// uses a cross-run open/close marker stack so nested marks nest correctly and
/// adjacent same-mark runs share markers — producing canonical output (no
/// `**a****b**`) which is what makes the round trip idempotent.
class MarkdownEncoder {
  const MarkdownEncoder({this.blockSeparator = '\n\n'});

  final String blockSeparator;

  /// Wrapping inline marks in nesting order (outer → inner) with their markers.
  static const List<String> _wrapping = [
    InlineAttr.bold,
    InlineAttr.italic,
    InlineAttr.strike,
  ];
  static const Map<String, String> _markers = {
    InlineAttr.bold: '**',
    InlineAttr.italic: '_',
    InlineAttr.strike: '~~',
  };

  String convert(Document doc) {
    final buf = StringBuffer();
    for (var i = 0; i < doc.nodes.length; i++) {
      if (i > 0) buf.write(_separatorBetween(doc.nodes[i - 1], doc.nodes[i]));
      buf.write(_encodeBlock(doc.nodes[i]));
    }
    return buf.toString();
  }

  /// Tight separator (single newline) between items of the same list family or
  /// consecutive quote lines; a blank line between everything else.
  String _separatorBetween(Node a, Node b) {
    if (a is TextBlockNode && b is TextBlockNode) {
      if (_sameListFamily(a.type, b.type)) return '\n';
      if (a.type == BlockType.quote && b.type == BlockType.quote) return '\n';
      // A definition term/desc is tight against a following description.
      if ((a.type == BlockType.definitionTerm ||
              a.type == BlockType.definitionDesc) &&
          b.type == BlockType.definitionDesc) {
        return '\n';
      }
    }
    return blockSeparator;
  }

  static bool _sameListFamily(String a, String b) {
    const bulleted = {BlockType.bulletedListItem, BlockType.todoListItem};
    if (bulleted.contains(a) && bulleted.contains(b)) return true;
    if (a == BlockType.numberedListItem && b == BlockType.numberedListItem) {
      return true;
    }
    return false;
  }

  String _encodeBlock(Node node) {
    if (node is CodeBlockNode) {
      return '```${node.language ?? ''}\n${node.code}\n```';
    }
    if (node is HorizontalRuleNode) {
      return '---';
    }
    if (node is ImageNode) {
      final title = node.title != null ? ' "${node.title}"' : '';
      return '![${node.alt ?? ''}](${node.url}$title)';
    }
    if (node is MathBlockNode) {
      return '\$\$\n${node.tex}\n\$\$';
    }
    if (node is TableNode) {
      return _encodeTable(node);
    }
    if (node is MermaidNode) {
      return '```mermaid\n${node.source}\n```';
    }
    if (node is FrontMatterNode) {
      return '---\n${node.yaml}\n---';
    }
    if (node is TextBlockNode) {
      final inline = _encodeDelta(node.delta);
      switch (node.type) {
        case BlockType.heading:
          final level = (node.level ?? 1).clamp(1, 6);
          return '${'#' * level} $inline';
        case BlockType.bulletedListItem:
          return '${'  ' * node.indent}- $inline';
        case BlockType.numberedListItem:
          return '${'  ' * node.indent}${node.number ?? 1}. $inline';
        case BlockType.todoListItem:
          return '${'  ' * node.indent}- [${(node.checked ?? false) ? 'x' : ' '}] $inline';
        case BlockType.quote:
          return '${'> ' * (node.indent + 1)}$inline';
        case BlockType.footnoteDef:
          return '[^${node.footnoteLabel ?? ''}]: $inline';
        case BlockType.definitionTerm:
          return inline;
        case BlockType.definitionDesc:
          return ': $inline';
        default:
          return inline;
      }
    }
    return '';
  }

  String _encodeTable(TableNode t) {
    String row(List<Delta> cells) =>
        '| ${[for (final c in cells) _encodeDelta(c)].join(' | ')} |';
    String divider(TableAlign a) => switch (a) {
          TableAlign.left => ':---',
          TableAlign.center => ':--:',
          TableAlign.right => '---:',
          TableAlign.none => '---',
        };
    final lines = <String>[];
    if (t.rows.isNotEmpty) lines.add(row(t.rows.first));
    lines.add('| ${t.alignments.map(divider).join(' | ')} |');
    for (final r in t.rows.skip(1)) {
      lines.add(row(r));
    }
    return lines.join('\n');
  }

  String _encodeDelta(Delta delta) {
    final buf = StringBuffer();
    final open = <String>[]; // marks currently open, outer-first

    void closeFrom(int idx) {
      for (var i = open.length - 1; i >= idx; i--) {
        buf.write(_markers[open[i]]);
      }
      open.removeRange(idx, open.length);
    }

    for (final run in delta.runs) {
      final attrs = run.attributes;
      final isCode = attrs[InlineAttr.code] == true;
      final link = attrs[InlineAttr.link] as String?;
      final footnote = attrs[InlineAttr.footnote] as String?;

      // A footnote reference is a self-contained token (`[^label]`); close any
      // open marks around it.
      if (footnote != null) {
        closeFrom(0);
        buf.write('[^$footnote]');
        continue;
      }

      // Inline math is a self-contained `$…$` token (run text is the LaTeX).
      if (attrs[InlineAttr.math] == true) {
        closeFrom(0);
        buf.write('\$${run.text}\$');
        continue;
      }

      // Code spans are literal and can't carry wrapping marks meaningfully;
      // close everything around them.
      final want = isCode
          ? const <String>[]
          : [for (final m in _wrapping) if (attrs[m] == true) m];

      var common = 0;
      while (common < open.length &&
          common < want.length &&
          open[common] == want[common]) {
        common++;
      }
      closeFrom(common);
      for (var i = common; i < want.length; i++) {
        buf.write(_markers[want[i]]);
        open.add(want[i]);
      }

      var text = isCode ? '`${run.text}`' : _escapeText(run.text);
      if (link != null) text = '[$text]($link)';
      buf.write(text);
    }
    closeFrom(0);
    return buf.toString();
  }

  static final RegExp _escapeChars = RegExp(r'([\\`*_~\[\]])');

  String _escapeText(String text) =>
      text.replaceAllMapped(_escapeChars, (m) => '\\${m[1]}');
}
