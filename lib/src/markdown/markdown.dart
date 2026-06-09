import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

import '../export/pdf_export.dart';
import '../model/delta.dart';
import '../model/document.dart';
import '../model/node.dart';
import 'block_codecs.dart';
import 'decoder.dart';
import 'encoder.dart';
import 'html_encoder.dart';

/// Convenience facade over the Markdown pipeline.
abstract final class Markdown {
  static final MarkdownDecoder _decoder = MarkdownDecoder();
  static const MarkdownEncoder _encoder = MarkdownEncoder();
  static const HtmlEncoder _htmlEncoder = HtmlEncoder();

  /// Parses Markdown [source] into a [Document]. Pass [codecs] to decode custom
  /// (plugin) blocks (fenced blocks whose info string names a registered codec).
  static Document parse(String source, {BlockCodecs codecs = const BlockCodecs()}) =>
      codecs.isEmpty
          ? _decoder.convert(source)
          : MarkdownDecoder(codecs: codecs).convert(source);

  /// Number of full-document serializations performed — a test/CI hook to prove
  /// the `markdown` getter is memoized (not re-serialized on every read).
  static int debugSerializeCount = 0;

  /// Serializes [document] to Markdown text. Pass [codecs] to encode custom
  /// (plugin) blocks back to their fenced Markdown form.
  static String serialize(Document document,
      {BlockCodecs codecs = const BlockCodecs()}) {
    debugSerializeCount++;
    return codecs.isEmpty
        ? _encoder.convert(document)
        : MarkdownEncoder(codecs: codecs).convert(document);
  }

  /// Serializes [document], also returning each block's start offset in the
  /// output (keyed by node id).
  static (String, Map<String, int>) serializeWithOffsets(Document document) =>
      _encoder.convertWithOffsets(document);

  /// Serializes [document] to semantic HTML.
  static String toHtml(Document document) => _htmlEncoder.convert(document);

  /// Exports [document] to a PDF byte stream (native pure-Dart writer; no
  /// WebView/JavaScript/dependency).
  static Uint8List toPdf(Document document) =>
      const PdfExporter().export(document);

  /// Parses Markdown [source] **off the main isolate** (via `compute`), so a
  /// large initial load doesn't jank the UI. Equivalent to [parse] but async;
  /// custom-block codecs aren't supported (closures can't cross isolates).
  static Future<Document> parseAsync(String source) =>
      compute(_parseIsolate, source);

  static Document _parseIsolate(String source) =>
      MarkdownDecoder().convert(source);

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
