import 'package:flutter/material.dart';

import '../diagram/mermaid_class.dart';
import '../diagram/mermaid_er.dart';
import '../diagram/mermaid_flowchart.dart';
import '../diagram/mermaid_gantt.dart';
import '../diagram/mermaid_journey.dart';
import '../diagram/mermaid_pie.dart';
import '../diagram/mermaid_sequence.dart';
import '../diagram/mermaid_state.dart';
import '../model/node.dart';
import '../theme/editor_style.dart';

/// Renders a [MermaidNode]. Pluggable so a host can supply a native diagram
/// engine; the default ([SourceCardDiagramRenderer]) always works on every
/// platform with no WebView/JS, degrading to a readable source card.
abstract class DiagramRenderer {
  Widget build(BuildContext context, MermaidNode node, EditorStyle style);
}

/// The native diagram engine: renders the diagram types it supports in pure
/// Dart (currently pie charts), and degrades to [fallback] (a source card) for
/// types not yet implemented. No WebView, no JavaScript.
class NativeDiagramRenderer implements DiagramRenderer {
  const NativeDiagramRenderer(
      {this.fallback = const SourceCardDiagramRenderer()});

  final DiagramRenderer fallback;

  @override
  Widget build(BuildContext context, MermaidNode node, EditorStyle style) {
    final pie = parsePie(node.source);
    if (pie != null) {
      return Container(
        key: ValueKey('markey-pie-${node.id}'),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.centerLeft,
        child: MermaidPieView(chart: pie, textStyle: style.baseTextStyle),
      );
    }
    final gantt = parseGantt(node.source);
    if (gantt != null) {
      return Container(
        key: ValueKey('markey-gantt-${node.id}'),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: GanttView(
            gantt: gantt,
            textStyle: style.baseTextStyle,
            barColor: style.caretColor.withValues(alpha: 0.7),
            lineColor: style.caretColor,
          ),
        ),
      );
    }
    final journey = parseJourney(node.source);
    if (journey != null) {
      return Container(
        key: ValueKey('markey-journey-${node.id}'),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: MermaidJourneyView(
            journey: journey,
            textStyle: style.baseTextStyle,
            lineColor: style.caretColor,
          ),
        ),
      );
    }
    final seq = parseSequence(node.source);
    if (seq != null) {
      return Container(
        key: ValueKey('markey-sequence-${node.id}'),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SequenceDiagramView(
            diagram: seq,
            textStyle: style.baseTextStyle,
            lineColor: style.caretColor,
          ),
        ),
      );
    }
    final cls = parseClassDiagram(node.source) ?? parseEntityRelationship(node.source);
    if (cls != null) {
      return Container(
        key: ValueKey('markey-class-${node.id}'),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ClassDiagramView(
            diagram: cls,
            textStyle: style.baseTextStyle,
            lineColor: style.caretColor,
            fillColor: style.codeTextStyle.backgroundColor ??
                style.caretColor.withValues(alpha: 0.08),
          ),
        ),
      );
    }
    final flow = parseFlowchart(node.source) ?? parseStateDiagram(node.source);
    if (flow != null) {
      return Container(
        key: ValueKey('markey-flowchart-${node.id}'),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: FlowchartView(
            chart: flow,
            textStyle: style.baseTextStyle,
            lineColor: style.caretColor,
            fillColor: style.codeTextStyle.backgroundColor ??
                style.caretColor.withValues(alpha: 0.08),
          ),
        ),
      );
    }
    return fallback.build(context, node, style);
  }
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
