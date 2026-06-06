import 'package:meta/meta.dart';

import '../model/document.dart';
import '../model/node.dart';

/// A located occurrence of a search query within a text block.
@immutable
class MatchLocation {
  const MatchLocation({
    required this.nodeId,
    required this.start,
    required this.end,
  });

  final String nodeId;
  final int start; // plain-text offset within the block
  final int end;

  @override
  bool operator ==(Object other) =>
      other is MatchLocation &&
      other.nodeId == nodeId &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(nodeId, start, end);

  @override
  String toString() => 'MatchLocation($nodeId, $start..$end)';
}

/// Returns every occurrence of [query] across the document's text blocks, in
/// document order. An empty query matches nothing.
List<MatchLocation> findInDocument(
  Document doc,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return const [];
  final needle = caseSensitive ? query : query.toLowerCase();
  final out = <MatchLocation>[];
  for (final node in doc.nodes) {
    if (node is! TextBlockNode) continue;
    final hay = caseSensitive
        ? node.delta.toPlainText()
        : node.delta.toPlainText().toLowerCase();
    var from = 0;
    while (true) {
      final i = hay.indexOf(needle, from);
      if (i < 0) break;
      out.add(MatchLocation(nodeId: node.id, start: i, end: i + query.length));
      from = i + query.length;
    }
  }
  return out;
}
