import 'package:flutter/widgets.dart';

import '../model/node.dart';
import '../theme/editor_style.dart';

/// Renders a custom (plugin) block. Receives the [CustomBlockNode] and the
/// resolved [EditorStyle].
typedef BlockBuilder = Widget Function(
    BuildContext context, CustomBlockNode node, EditorStyle style);

/// An open registry of block renderers (§13.5 / ADR-008) — the seam that turns
/// the closed `sealed`+`switch` block set into an extensible one. A host
/// registers a [BlockBuilder] for a `blockType`; the editor renders any
/// [CustomBlockNode] of that type through it.
///
/// (Decode/encode registration for custom blocks builds on this same registry;
/// rendering is the first, most-requested extension point.)
class BlockRegistry {
  BlockRegistry([Map<String, BlockBuilder>? builders])
      : _builders = {...?builders};

  final Map<String, BlockBuilder> _builders;

  void register(String blockType, BlockBuilder builder) =>
      _builders[blockType] = builder;

  bool has(String blockType) => _builders.containsKey(blockType);

  BlockBuilder? builderFor(String blockType) => _builders[blockType];
}
