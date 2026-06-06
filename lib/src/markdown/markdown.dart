import '../model/document.dart';
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
}
