import '../model/delta.dart';
import '../model/document.dart';
import '../model/node.dart';
import 'decoder.dart';
import 'encoder.dart';
import 'html_encoder.dart';

/// Convenience facade over the Markdown pipeline.
abstract final class Markdown {
  static final MarkdownDecoder _decoder = MarkdownDecoder();
  static const MarkdownEncoder _encoder = MarkdownEncoder();
  static const HtmlEncoder _htmlEncoder = HtmlEncoder();

  /// Parses Markdown [source] into a [Document].
  static Document parse(String source) => _decoder.convert(source);

  /// Serializes [document] to Markdown text.
  static String serialize(Document document) => _encoder.convert(document);

  /// Serializes [document], also returning each block's start offset in the
  /// output (keyed by node id).
  static (String, Map<String, int>) serializeWithOffsets(Document document) =>
      _encoder.convertWithOffsets(document);

  /// Serializes [document] to semantic HTML.
  static String toHtml(Document document) => _htmlEncoder.convert(document);

  /// Parses an inline-Markdown fragment into a [Delta] (used for table cells).
  static Delta inlineToDelta(String source) {
    final first = _decoder.convert(source).nodes.first;
    return first is TextBlockNode ? first.delta : Delta.empty();
  }

  /// Serializes a [Delta] to inline Markdown.
  static String deltaToInline(Delta delta) => _encoder.encodeInline(delta);
}

/// Convenience: parse Markdown straight to HTML.
extension MarkdownToHtml on String {
  /// Treats this string as Markdown and returns its HTML rendering.
  String markdownToHtml() => Markdown.toHtml(Markdown.parse(this));
}
