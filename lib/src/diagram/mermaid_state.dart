import 'mermaid_flowchart.dart';

final RegExp _first = RegExp(r'^stateDiagram(-v2)?(\s|$)');
final RegExp _transition =
    RegExp(r'^(\[\*\]|\w+)\s*-->\s*(\[\*\]|\w+)(?:\s*:\s*(.+))?$');

/// Parses a Mermaid `stateDiagram` into the shared [Flowchart] model (states as
/// nodes, transitions as edges), so it reuses the native flowchart renderer.
/// `[*]` becomes a pseudo start/end circle node. Pure Dart — no JS.
Flowchart? parseStateDiagram(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !_first.hasMatch(lines.first)) return null;

  final nodes = <String, FlowNode>{};
  final edges = <FlowEdge>[];
  var pseudo = 0;

  String resolve(String token, {required bool isSource}) {
    if (token == '[*]') {
      // Distinct id per occurrence so start and end are separate nodes.
      final id = isSource && pseudo == 0 ? '__start' : '__pseudo${pseudo++}';
      nodes[id] = FlowNode(id, '●', FlowShape.circle);
      return id;
    }
    nodes.putIfAbsent(token, () => FlowNode(token, token, FlowShape.rounded));
    return token;
  }

  for (final line in lines.skip(1)) {
    final m = _transition.firstMatch(line);
    if (m == null) continue;
    final from = resolve(m.group(1)!, isSource: true);
    final to = resolve(m.group(2)!, isSource: false);
    edges.add(FlowEdge(from, to, m.group(3)?.trim()));
  }
  if (nodes.isEmpty || edges.isEmpty) return null;
  return Flowchart(FlowDirection.topDown, nodes, edges);
}
