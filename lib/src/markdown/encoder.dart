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
    final parts = <String>[];
    for (final node in doc.nodes) {
      parts.add(_encodeBlock(node));
    }
    return parts.join(blockSeparator);
  }

  String _encodeBlock(Node node) {
    if (node is TextBlockNode) {
      final inline = _encodeDelta(node.delta);
      if (node.type == BlockType.heading) {
        final level = (node.level ?? 1).clamp(1, 6);
        return '${'#' * level} $inline';
      }
      return inline;
    }
    return '';
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
