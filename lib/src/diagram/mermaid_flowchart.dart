import 'dart:math' as math;

import 'package:flutter/material.dart';

enum FlowDirection { topDown, leftRight }

enum FlowShape { rect, rounded, diamond, circle, stadium }

@immutable
class FlowNode {
  const FlowNode(this.id, this.label, this.shape);
  final String id;
  final String label;
  final FlowShape shape;
}

@immutable
class FlowEdge {
  const FlowEdge(this.from, this.to, this.label);
  final String from;
  final String to;
  final String? label;
}

/// A parsed Mermaid `graph`/`flowchart`.
class Flowchart {
  Flowchart(this.direction, this.nodes, this.edges);
  final FlowDirection direction;
  final Map<String, FlowNode> nodes; // insertion-ordered
  final List<FlowEdge> edges;

  /// Longest-path rank for each node (roots = 0), cycle-safe.
  Map<String, int> ranks() {
    final adj = <String, List<String>>{for (final id in nodes.keys) id: []};
    final indeg = <String, int>{for (final id in nodes.keys) id: 0};
    for (final e in edges) {
      if (!nodes.containsKey(e.from) || !nodes.containsKey(e.to)) continue;
      adj[e.from]!.add(e.to);
      indeg[e.to] = indeg[e.to]! + 1;
    }
    final rank = <String, int>{for (final id in nodes.keys) id: 0};
    // Kahn-style longest path; nodes with no in-edges start at 0.
    final queue = <String>[
      for (final id in nodes.keys) if (indeg[id] == 0) id
    ];
    final remaining = Map<String, int>.from(indeg);
    final seen = <String>{};
    while (queue.isNotEmpty) {
      final n = queue.removeAt(0);
      if (!seen.add(n)) continue;
      for (final m in adj[n]!) {
        if (rank[m]! < rank[n]! + 1) rank[m] = rank[n]! + 1;
        remaining[m] = remaining[m]! - 1;
        if (remaining[m]! <= 0) queue.add(m);
      }
    }
    return rank;
  }
}

final RegExp _first = RegExp(r'^(graph|flowchart)\s+(TD|TB|LR|RL|BT)?');
final String _shapePattern =
    r'(\[[^\]]*\]|\(\([^)]*\)\)|\([^)]*\)|\{[^}]*\}|\[\[[^\]]*\]\])';
final RegExp _edge = RegExp(
    r'^(\w+)\s*' + _shapePattern + r'?\s*(?:-->|---|==>|-\.->)(?:\|([^|]*)\|)?\s*(\w+)\s*' +
        _shapePattern + r'?$');
final RegExp _nodeOnly = RegExp(r'^(\w+)\s*' + _shapePattern + r'?$');

(FlowShape, String) _shapeAndLabel(String id, String? token) {
  if (token == null || token.isEmpty) return (FlowShape.rect, id);
  if (token.startsWith('((')) {
    return (FlowShape.circle, token.substring(2, token.length - 2).trim());
  }
  if (token.startsWith('[[')) {
    return (FlowShape.stadium, token.substring(2, token.length - 2).trim());
  }
  if (token.startsWith('[')) {
    return (FlowShape.rect, token.substring(1, token.length - 1).trim());
  }
  if (token.startsWith('{')) {
    return (FlowShape.diamond, token.substring(1, token.length - 1).trim());
  }
  if (token.startsWith('(')) {
    return (FlowShape.rounded, token.substring(1, token.length - 1).trim());
  }
  return (FlowShape.rect, id);
}

/// Parses a Mermaid flowchart, or null if [source] isn't one (or is empty).
/// Pure Dart — part of the native, no-JS diagram engine.
Flowchart? parseFlowchart(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty) return null;
  final head = _first.firstMatch(lines.first);
  if (head == null) return null;
  final dir = (head.group(2) == 'LR' || head.group(2) == 'RL')
      ? FlowDirection.leftRight
      : FlowDirection.topDown;

  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];

  void put(String id, String? token) {
    final (shape, label) = _shapeAndLabel(id, token);
    // A later labelled mention upgrades a bare node.
    final existing = nodes[id];
    if (existing == null || (existing.label == id && label != id)) {
      nodes[id] = FlowNode(id, label, shape);
    }
  }

  for (final line in lines.skip(1)) {
    final e = _edge.firstMatch(line);
    if (e != null) {
      put(e.group(1)!, e.group(2));
      put(e.group(4)!, e.group(5));
      edges.add(FlowEdge(e.group(1)!, e.group(4)!, e.group(3)?.trim()));
      continue;
    }
    final n = _nodeOnly.firstMatch(line);
    if (n != null) put(n.group(1)!, n.group(2));
  }
  if (nodes.isEmpty) return null;
  return Flowchart(dir, nodes, edges);
}

/// Renders a [Flowchart] natively with a simple layered layout.
class FlowchartView extends StatelessWidget {
  const FlowchartView({
    super.key,
    required this.chart,
    required this.textStyle,
    required this.lineColor,
    required this.fillColor,
  });
  final Flowchart chart;
  final TextStyle textStyle;
  final Color lineColor;
  final Color fillColor;

  static const double _nodeW = 120;
  static const double _nodeH = 44;
  static const double _gapX = 36;
  static const double _gapY = 40;

  Map<String, Offset> _positions() {
    final ranks = chart.ranks();
    final byRank = <int, List<String>>{};
    for (final id in chart.nodes.keys) {
      byRank.putIfAbsent(ranks[id]!, () => []).add(id);
    }
    final pos = <String, Offset>{};
    final maxInRank =
        byRank.values.fold<int>(0, (m, l) => math.max(m, l.length));
    byRank.forEach((rank, ids) {
      for (var i = 0; i < ids.length; i++) {
        // Center each rank's row.
        final offset = (maxInRank - ids.length) / 2;
        final col = i + offset;
        final along = col * (_nodeW + _gapX) + _nodeW / 2;
        final across = rank * (_nodeH + _gapY) + _nodeH / 2;
        pos[ids[i]] = chart.direction == FlowDirection.topDown
            ? Offset(along, across)
            : Offset(across, along);
      }
    });
    return pos;
  }

  @override
  Widget build(BuildContext context) {
    final pos = _positions();
    var maxX = 0.0, maxY = 0.0;
    for (final p in pos.values) {
      maxX = math.max(maxX, p.dx + _nodeW / 2);
      maxY = math.max(maxY, p.dy + _nodeH / 2);
    }
    return SizedBox(
      width: maxX + 8,
      height: maxY + 8,
      child: CustomPaint(
        painter: _FlowPainter(chart, pos, textStyle, lineColor, fillColor),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(
      this.chart, this.pos, this.textStyle, this.lineColor, this.fillColor);
  final Flowchart chart;
  final Map<String, Offset> pos;
  final TextStyle textStyle;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final fill = Paint()..color = fillColor;

    // Edges first (under nodes).
    for (final e in chart.edges) {
      final a = pos[e.from], b = pos[e.to];
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, stroke);
      _arrow(canvas, a, b, lineColor);
      if (e.label != null && e.label!.isNotEmpty) {
        _label(canvas, e.label!, (a + b) / 2, fill: size);
      }
    }

    for (final node in chart.nodes.values) {
      final c = pos[node.id];
      if (c == null) continue;
      _drawShape(canvas, node, c, fill, stroke);
      _label(canvas, node.label, c);
    }
  }

  void _drawShape(Canvas canvas, FlowNode node, Offset c, Paint fill, Paint stroke) {
    final rect = Rect.fromCenter(
        center: c, width: FlowchartView._nodeW, height: FlowchartView._nodeH);
    switch (node.shape) {
      case FlowShape.diamond:
        final p = Path()
          ..moveTo(c.dx, rect.top)
          ..lineTo(rect.right, c.dy)
          ..lineTo(c.dx, rect.bottom)
          ..lineTo(rect.left, c.dy)
          ..close();
        canvas..drawPath(p, fill)..drawPath(p, stroke);
      case FlowShape.circle:
        final r = FlowchartView._nodeH / 2;
        canvas..drawCircle(c, r, fill)..drawCircle(c, r, stroke);
      case FlowShape.rounded:
      case FlowShape.stadium:
        final rr = RRect.fromRectAndRadius(
            rect, const Radius.circular(FlowchartView._nodeH / 2));
        canvas..drawRRect(rr, fill)..drawRRect(rr, stroke);
      case FlowShape.rect:
        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(4));
        canvas..drawRRect(rr, fill)..drawRRect(rr, stroke);
    }
  }

  void _label(Canvas canvas, String text, Offset center, {Size? fill}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: FlowchartView._nodeW - 12);
    if (fill != null) {
      // edge label: paint a small background for legibility
      final r = Rect.fromCenter(
              center: center, width: tp.width + 6, height: tp.height + 2)
          .translate(0, 0);
      canvas.drawRect(r, Paint()..color = const Color(0xFFFFFFFF));
    }
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Color color) {
    final dir = (to - from);
    final len = dir.distance;
    if (len == 0) return;
    final u = dir / len;
    // stop the arrow at the node's edge box approximately
    final tip = to - u * (FlowchartView._nodeH / 2);
    final left = tip - u * 8 + Offset(-u.dy, u.dx) * 4;
    final right = tip - u * 8 + Offset(u.dy, -u.dx) * 4;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FlowPainter old) => old.chart != chart;
}
