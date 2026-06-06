import 'package:flutter/material.dart';

import '../model/node.dart';
import '../theme/editor_style.dart';

/// Renders a [MermaidNode]. Pluggable so a host can supply a native diagram
/// engine; the default ([SourceCardDiagramRenderer]) always works on every
/// platform with no WebView/JS, degrading to a readable source card.
abstract class DiagramRenderer {
  Widget build(BuildContext context, MermaidNode node, EditorStyle style);
}

/// The always-available native fallback: shows the diagram source in a styled
/// card with a "mermaid" badge. A future native engine (parser → layout →
/// CustomPainter) plugs in behind the same interface.
class SourceCardDiagramRenderer implements DiagramRenderer {
  const SourceCardDiagramRenderer();

  @override
  Widget build(BuildContext context, MermaidNode node, EditorStyle style) {
    final mono = style.codeTextStyle.copyWith(backgroundColor: null);
    final accent = style.caretColor;
    return Container(
      key: ValueKey('markey-mermaid-${node.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.codeTextStyle.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_tree, size: 16,
                  color: accent.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text('mermaid',
                  style: mono.copyWith(
                    fontSize: (mono.fontSize ?? 14) * 0.8,
                    color: accent.withValues(alpha: 0.7),
                  )),
            ],
          ),
          const SizedBox(height: 6),
          Text(node.source, style: mono),
        ],
      ),
    );
  }
}
