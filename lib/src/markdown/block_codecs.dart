import '../model/node.dart';

/// A Markdown decode/encode codec for a custom (plugin) block, so a
/// [CustomBlockNode] round-trips through Markdown losslessly. The block is
/// written as a fenced block whose info string is the codec's [fence] (e.g. a
/// fence of `chart` round-trips `CustomBlockNode(blockType: …)` to and from a
/// ` ```chart ` fenced block carrying its content).
///
/// This is the decode/encode half of the open block set (§13.5) — pairs with
/// the render-side `BlockRegistry`.
class CustomBlockCodec {
  const CustomBlockCodec({
    required this.blockType,
    required this.fence,
    required this.decode,
    required this.encode,
  });

  /// The [CustomBlockNode.blockType] this codec produces/consumes.
  final String blockType;

  /// The fenced-block info string that identifies this block (e.g. `chart`).
  final String fence;

  /// Parses the fenced block's content into the node's `data` map.
  final Map<String, Object?> Function(String content) decode;

  /// Serializes the node's `data` back to the fenced block's content.
  final String Function(CustomBlockNode node) encode;
}

/// A registry of [CustomBlockCodec]s threaded into `Markdown.parse` / `serialize`
/// so custom blocks decode from and encode to Markdown.
class BlockCodecs {
  const BlockCodecs([this._codecs = const []]);

  final List<CustomBlockCodec> _codecs;

  bool get isEmpty => _codecs.isEmpty;

  /// The codec whose [CustomBlockCodec.fence] equals [fence], or null.
  CustomBlockCodec? byFence(String? fence) {
    if (fence == null) return null;
    for (final c in _codecs) {
      if (c.fence == fence) return c;
    }
    return null;
  }

  /// The codec for [blockType], or null.
  CustomBlockCodec? byType(String blockType) {
    for (final c in _codecs) {
      if (c.blockType == blockType) return c;
    }
    return null;
  }
}
