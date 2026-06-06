import '../model/delta.dart';
import '../model/document.dart';
import '../model/node.dart';
import 'decoder.dart';
import 'encoder.dart';

/// Convenience facade over the Markdown pipeline.
abstract final class Markdown {
  static final MarkdownDecoder _decoder = MarkdownDecoder();
  static const MarkdownEncoder _encoder = MarkdownEncoder();

  /// Parses Markdown [source] into a [Document].
  static Document parse(String source) => _decoder.convert(source);

  /// Serializes [document] to Markdown text.
  static String serialize(Document document) => _encoder.convert(document);

  /// Parses an inline-Markdown fragment into a [Delta] (used for table cells).
  static Delta inlineToDelta(String source) {
    final first = _decoder.convert(source).nodes.first;
    return first is TextBlockNode ? first.delta : Delta.empty();
  }

  /// Serializes a [Delta] to inline Markdown.
  static String deltaToInline(Delta delta) => _encoder.encodeInline(delta);
}
