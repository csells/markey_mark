import '../model/attributes.dart';
import '../model/delta.dart';
import '../model/document.dart';
import '../model/node.dart';
import 'block_codecs.dart';

/// Serializes a [Document] to Markdown text.
///
/// We own this (the `markdown` package ships no serializer). The inline encoder
/// uses a cross-run open/close marker stack so nested marks nest correctly and
/// adjacent same-mark runs share markers — producing canonical output (no
/// `**a****b**`) which is what makes the round trip idempotent.
class MarkdownEncoder {
  const MarkdownEncoder(
      {this.blockSeparator = '\n\n', this.codecs = const BlockCodecs()});

  final String blockSeparator;

  /// Codecs for custom (plugin) blocks; a [CustomBlockNode] is serialized as a
  /// fenced block via its codec.
  final BlockCodecs codecs;

  /// Wrapping inline marks in nesting order (outer → inner) with their markers.
  static const List<String> _wrapping = [
    InlineAttr.highlight,
    InlineAttr.bold,
    InlineAttr.italic,
    InlineAttr.strike,
  ];
  static const Map<String, String> _markers = {
    InlineAttr.highlight: '==',
    InlineAttr.bold: '**',
    InlineAttr.italic: '_',
    InlineAttr.strike: '~~',
  };

  String convert(Document doc) => convertWithOffsets(doc).$1;

  /// Like [convert], but also returns the start offset of each block's text in
  /// the serialized output, keyed by node id (used to map a caret between the
  /// WYSIWYG document and the raw source).
  (String, Map<String, int>) convertWithOffsets(Document doc) {
    final buf = StringBuffer();
    final starts = <String, int>{};
    // Content column (indent of children) per list-nesting level, so nested
    // items are indented enough to nest under markers of any width.
    final contentCol = <int>[];
    // Canonical sequential numbering per ordered-list level, so re-parsing
    // (which numbers by position) reproduces the same Markdown.
    final orderedNum = <int, int>{};
    for (var i = 0; i < doc.nodes.length; i++) {
      final node = doc.nodes[i];
      if (i > 0) buf.write(_separatorBetween(doc.nodes[i - 1], node));
      var leading = '';
      int? orderedOverride;
      if (node is TextBlockNode && _isListItem(node.type)) {
        final level = node.indent;
        final lead = level == 0
            ? 0
            : (contentCol.length >= level
                ? contentCol[level - 1]
                : (contentCol.isEmpty ? 0 : contentCol.last));
        leading = ' ' * lead;
        if (contentCol.length > level) contentCol.length = level;
        while (contentCol.length < level) {
          contentCol.add(contentCol.isEmpty ? 2 : contentCol.last + 2);
        }
        contentCol.add(lead + _markerWidth(node));
        orderedNum.removeWhere((lvl, _) => lvl > level); // deeper runs ended
        if (node.type == BlockType.numberedListItem) {
          orderedOverride =
              orderedNum.containsKey(level) ? orderedNum[level]! + 1 : (node.number ?? 1);
          orderedNum[level] = orderedOverride;
        } else {
          orderedNum.remove(level); // a bullet/task ends the ordered run here
        }
      } else {
        contentCol.clear();
        orderedNum.clear();
      }
      starts[node.id] = buf.length;
      buf.write(
          _encodeBlock(node, i > 0 ? doc.nodes[i - 1] : null, leading, orderedOverride));
    }
    return (buf.toString(), starts);
  }

  static bool _isListItem(String type) =>
      type == BlockType.bulletedListItem ||
      type == BlockType.numberedListItem ||
      type == BlockType.todoListItem;

  // The *list marker* width for nesting (the checkbox in a task item is part of
  // the content, so children nest under the `- `, i.e. width 2).
  static int _markerWidth(TextBlockNode node) => switch (node.type) {
        BlockType.numberedListItem => '${node.number ?? 1}. '.length,
        _ => 2, // '- ' (bullets and task items)
      };

  /// Tight separator (single newline) between items of the same list family or
  /// consecutive quote lines; a blank line between everything else.
  String _separatorBetween(Node a, Node b) {
    if (a is TextBlockNode && b is TextBlockNode) {
      if (_sameListFamily(a.type, b.type)) return '\n';
      if (a.type == BlockType.quote && b.type == BlockType.quote) {
        // Consecutive quote *paragraphs* re-parse as one block unless separated
        // by a quoted blank line; a different callout kind starts a new
        // blockquote entirely (a plain blank line).
        return a.callout == b.callout ? '\n>\n' : '\n\n';
      }
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

  String _encodeBlock(Node node,
      [Node? prev, String leading = '', int? orderedNumber]) {
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
    if (node is HtmlBlockNode) {
      return node.html; // verbatim — never escaped
    }
    if (node is CustomBlockNode) {
      final codec = codecs.byType(node.blockType);
      if (codec != null) {
        return '```${codec.fence}\n${codec.encode(node)}\n```';
      }
      return ''; // unknown custom block with no codec: nothing to serialize
    }
    if (node is TextBlockNode) {
      final inline = _encodeDelta(node.delta);
      switch (node.type) {
        case BlockType.heading:
          final level = (node.level ?? 1).clamp(1, 6);
          // ATX headings are single-line; flatten any soft breaks (e.g. from a
          // multi-line setext heading) to spaces.
          return '${'#' * level} ${inline.replaceAll('\n', ' ')}';
        case BlockType.bulletedListItem:
          return '$leading- $inline';
        case BlockType.numberedListItem:
          return '$leading${orderedNumber ?? node.number ?? 1}. $inline';
        case BlockType.todoListItem:
          return '$leading- [${(node.checked ?? false) ? 'x' : ' '}] $inline';
        case BlockType.quote:
          final prefix = '> ' * (node.indent + 1);
          final callout = node.callout;
          // Emit the `> [!KIND]` marker once, before the first block of a run.
          final isRunStart = !(prev is TextBlockNode &&
              prev.type == BlockType.quote &&
              prev.callout == callout);
          final marker = (callout != null && isRunStart)
              ? '> [!${callout.toUpperCase()}]\n'
              : '';
          return '$marker$prefix$inline';
        case BlockType.footnoteDef:
          return '[^${node.footnoteLabel ?? ''}]: $inline';
        case BlockType.definitionTerm:
          return _escapeLeadingBlockMarker(inline);
        case BlockType.definitionDesc:
          return ': $inline';
        default:
          return _escapeLeadingBlockMarker(inline);
      }
    }
    return '';
  }

  // Block-start markers that the inline escaper (`_escapeText`) doesn't cover:
  // ATX heading, blockquote, bullet/ordered list. A leading match would make a
  // paragraph re-parse as that block, so escape the trigger character.
  static final RegExp _leadingHeading = RegExp(r'^(#{1,6})(\s|$)');
  static final RegExp _leadingBullet = RegExp(r'^([-+])(\s|$)');
  static final RegExp _leadingOrdered = RegExp(r'^(\d+)([.)])(\s|$)');

  String _escapeLeadingBlockMarker(String s) {
    if (_leadingHeading.hasMatch(s) || s.startsWith('>') ||
        _leadingBullet.hasMatch(s)) {
      return '\\$s';
    }
    final m = _leadingOrdered.firstMatch(s);
    if (m != null) {
      // Escape the delimiter (`.`/`)`) so "1. x" → "1\. x".
      final n = m.group(1)!;
      return '$n\\${s.substring(n.length)}';
    }
    return s;
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

  /// Serializes a single [Delta] to inline Markdown (used for table cells).
  String encodeInline(Delta delta) => _encodeDelta(delta);

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

      // A hard line break: two trailing spaces + newline.
      if (attrs[InlineAttr.hardBreak] == true) {
        closeFrom(0);
        buf.write('  \n');
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

      var text = isCode ? _encodeCodeSpan(run.text) : _escapeText(run.text);
      if (link != null) text = '[$text]($link)';
      buf.write(text);
    }
    closeFrom(0);
    return buf.toString();
  }

  /// Encodes inline code with CommonMark-correct backtick fencing: the fence is
  /// one longer than the longest backtick run in the content, with space padding
  /// when the content begins/ends with a backtick (or is all spaces).
  static String _encodeCodeSpan(String content) {
    var longest = 0, current = 0;
    for (final unit in content.codeUnits) {
      if (unit == 0x60) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    final fence = '`' * (longest + 1);
    // Pad only to separate a leading/trailing backtick from the fence; an
    // all-spaces span needs no padding (and padding it would grow each pass).
    final needsPad =
        content.startsWith('`') || content.endsWith('`');
    final inner = needsPad ? ' $content ' : content;
    return '$fence$inner$fence';
  }

  static final RegExp _escapeChars = RegExp(r'([\\`*_~\[\]$])');

  String _escapeText(String text) =>
      text.replaceAllMapped(_escapeChars, (m) => '\\${m[1]}');
}
