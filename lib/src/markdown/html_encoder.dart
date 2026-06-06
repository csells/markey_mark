import '../model/attributes.dart';
import '../model/delta.dart';
import '../model/document.dart';
import '../model/node.dart';

/// Serializes a [Document] to semantic, self-contained HTML.
///
/// Pure Dart, no JavaScript: math is emitted in `math` spans/divs (the host may
/// style or post-process them) and Mermaid blocks as `<pre class="mermaid">`,
/// so the export works on every platform. Blocks are joined with newlines;
/// adjacent list items and quote lines are grouped into a single element.
class HtmlEncoder {
  const HtmlEncoder();

  static const Map<String, String> _wrappingTags = {
    InlineAttr.bold: 'strong',
    InlineAttr.italic: 'em',
    InlineAttr.strike: 'del',
  };
  static const List<String> _wrappingOrder = [
    InlineAttr.bold,
    InlineAttr.italic,
    InlineAttr.strike,
  ];

  String convert(Document doc) {
    final out = <String>[];
    final nodes = doc.nodes;
    var i = 0;
    while (i < nodes.length) {
      final node = nodes[i];
      if (node is TextBlockNode && _isListItem(node.type)) {
        final family = _listFamily(node.type);
        var j = i;
        while (j < nodes.length &&
            nodes[j] is TextBlockNode &&
            _isListItem((nodes[j] as TextBlockNode).type) &&
            _listFamily((nodes[j] as TextBlockNode).type) == family) {
          j++;
        }
        out.add(_renderList(
            nodes.sublist(i, j).cast<TextBlockNode>(), family, 0));
        i = j;
      } else if (node is TextBlockNode && node.type == BlockType.quote) {
        var j = i;
        while (j < nodes.length &&
            nodes[j] is TextBlockNode &&
            (nodes[j] as TextBlockNode).type == BlockType.quote &&
            (nodes[j] as TextBlockNode).callout == node.callout) {
          j++;
        }
        final quotes = nodes.sublist(i, j).cast<TextBlockNode>();
        final lines =
            quotes.map((n) => '<p>${_inline(n.delta)}</p>').join('\n');
        final callout = quotes.first.callout;
        if (callout != null) {
          out.add('<div class="callout callout-$callout">\n$lines\n</div>');
        } else {
          out.add('<blockquote>\n$lines\n</blockquote>');
        }
        i = j;
      } else if (node is TextBlockNode &&
          (node.type == BlockType.definitionTerm ||
              node.type == BlockType.definitionDesc)) {
        var j = i;
        while (j < nodes.length &&
            nodes[j] is TextBlockNode &&
            ((nodes[j] as TextBlockNode).type == BlockType.definitionTerm ||
                (nodes[j] as TextBlockNode).type == BlockType.definitionDesc)) {
          j++;
        }
        out.add(_renderDefinitionList(
            nodes.sublist(i, j).cast<TextBlockNode>()));
        i = j;
      } else {
        final leaf = _leaf(node);
        if (leaf != null) out.add(leaf);
        i++;
      }
    }
    return out.join('\n');
  }

  // ---- leaf (non-grouped) blocks ----

  String? _leaf(Node node) {
    if (node is CodeBlockNode) {
      final cls =
          node.language != null ? ' class="language-${node.language}"' : '';
      return '<pre><code$cls>${_escape(node.code)}</code></pre>';
    }
    if (node is HorizontalRuleNode) return '<hr>';
    if (node is ImageNode) {
      final title =
          node.title != null ? ' title="${_escapeAttr(node.title!)}"' : '';
      return '<p><img src="${_escapeAttr(node.url)}" '
          'alt="${_escapeAttr(node.alt ?? '')}"$title></p>';
    }
    if (node is MathBlockNode) {
      return '<div class="math math-display">${_escape(node.tex)}</div>';
    }
    if (node is MermaidNode) {
      return '<pre class="mermaid">${_escape(node.source)}</pre>';
    }
    if (node is TableNode) return _renderTable(node);
    if (node is FrontMatterNode) return null; // metadata, not body content
    if (node is TextBlockNode) {
      final inline = _inline(node.delta);
      switch (node.type) {
        case BlockType.heading:
          final level = (node.level ?? 1).clamp(1, 6);
          return '<h$level>$inline</h$level>';
        case BlockType.footnoteDef:
          return '<div class="footnote" id="fn-${node.footnoteLabel ?? ''}">'
              '<p>$inline</p></div>';
        default:
          return '<p>$inline</p>';
      }
    }
    return null;
  }

  // ---- lists ----

  static bool _isListItem(String type) =>
      type == BlockType.bulletedListItem ||
      type == BlockType.numberedListItem ||
      type == BlockType.todoListItem;

  /// 'ol' for numbered items, 'ul' for bullets and tasks.
  static String _listFamily(String type) =>
      type == BlockType.numberedListItem ? 'ol' : 'ul';

  String _renderList(List<TextBlockNode> items, String tag, int indent) {
    final hasTask = items
        .where((n) => n.indent == indent)
        .any((n) => n.type == BlockType.todoListItem);
    final cls = hasTask && tag == 'ul' ? ' class="task-list"' : '';
    final buf = StringBuffer('<$tag$cls>\n');
    var i = 0;
    while (i < items.length) {
      final item = items[i];
      buf.write('<li>');
      if (item.type == BlockType.todoListItem) {
        final checked = (item.checked ?? false) ? ' checked' : '';
        buf.write('<input type="checkbox"$checked disabled> ');
      }
      buf.write(_inline(item.delta));
      // Gather a deeper-indented run as a nested sublist.
      var j = i + 1;
      while (j < items.length && items[j].indent > item.indent) {
        j++;
      }
      if (j > i + 1) {
        final children = items.sublist(i + 1, j);
        buf.write('\n');
        buf.write(_renderList(children, _listFamily(children.first.type),
            children.first.indent));
        buf.write('\n');
      }
      buf.write('</li>\n');
      i = j;
    }
    buf.write('</$tag>');
    return buf.toString();
  }

  String _renderDefinitionList(List<TextBlockNode> items) {
    final buf = StringBuffer('<dl>\n');
    for (final item in items) {
      final tag = item.type == BlockType.definitionTerm ? 'dt' : 'dd';
      buf.write('<$tag>${_inline(item.delta)}</$tag>\n');
    }
    buf.write('</dl>');
    return buf.toString();
  }

  // ---- tables ----

  String _renderTable(TableNode t) {
    String styleFor(TableAlign a) => switch (a) {
          TableAlign.left => ' style="text-align: left"',
          TableAlign.center => ' style="text-align: center"',
          TableAlign.right => ' style="text-align: right"',
          TableAlign.none => '',
        };
    String cells(List<Delta> row, String cellTag) {
      final buf = StringBuffer();
      for (var c = 0; c < row.length; c++) {
        final align = c < t.alignments.length
            ? styleFor(t.alignments[c])
            : '';
        buf.write('<$cellTag$align>${_inline(row[c])}</$cellTag>');
      }
      return buf.toString();
    }

    final buf = StringBuffer('<table>\n');
    if (t.rows.isNotEmpty) {
      buf.write('<thead>\n<tr>${cells(t.rows.first, 'th')}</tr>\n</thead>\n');
    }
    if (t.rows.length > 1) {
      buf.write('<tbody>\n');
      for (final row in t.rows.skip(1)) {
        buf.write('<tr>${cells(row, 'td')}</tr>\n');
      }
      buf.write('</tbody>\n');
    }
    buf.write('</table>');
    return buf.toString();
  }

  // ---- inline ----

  String _inline(Delta delta) {
    final buf = StringBuffer();
    final open = <String>[]; // open wrapping tag names, outer-first

    void closeFrom(int idx) {
      for (var i = open.length - 1; i >= idx; i--) {
        buf.write('</${open[i]}>');
      }
      open.removeRange(idx, open.length);
    }

    for (final run in delta.runs) {
      final attrs = run.attributes;

      final footnote = attrs[InlineAttr.footnote] as String?;
      if (footnote != null) {
        closeFrom(0);
        buf.write('<sup><a href="#fn-$footnote" id="fnref-$footnote">'
            '$footnote</a></sup>');
        continue;
      }
      if (attrs[InlineAttr.math] == true) {
        closeFrom(0);
        buf.write('<span class="math math-inline">${_escape(run.text)}</span>');
        continue;
      }
      if (attrs[InlineAttr.hardBreak] == true) {
        closeFrom(0);
        buf.write('<br>');
        continue;
      }

      final isCode = attrs[InlineAttr.code] == true;
      final want = isCode
          ? const <String>[]
          : [
              for (final m in _wrappingOrder)
                if (attrs[m] == true) _wrappingTags[m]!,
            ];

      var common = 0;
      while (common < open.length &&
          common < want.length &&
          open[common] == want[common]) {
        common++;
      }
      closeFrom(common);
      for (var i = common; i < want.length; i++) {
        buf.write('<${want[i]}>');
        open.add(want[i]);
      }

      var text =
          isCode ? '<code>${_escape(run.text)}</code>' : _escape(run.text);
      final link = attrs[InlineAttr.link] as String?;
      if (link != null) text = '<a href="${_escapeAttr(link)}">$text</a>';
      buf.write(text);
    }
    closeFrom(0);
    return buf.toString();
  }

  // ---- escaping ----

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _escapeAttr(String s) => _escape(s).replaceAll('"', '&quot;');
}
