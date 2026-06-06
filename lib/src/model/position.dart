import 'package:flutter/painting.dart' show TextAffinity;
import 'package:meta/meta.dart';

/// A node-type-specific coordinate within a single node.
///
/// Text nodes use [TextNodePosition]; atomic nodes (image, rule, math block,
/// mermaid) use [AtomicNodePosition] (the super_editor
/// upstream/downstream idea).
@immutable
sealed class NodePosition {
  const NodePosition();
}

/// A caret offset within a text node's content.
@immutable
final class TextNodePosition extends NodePosition {
  const TextNodePosition(this.offset, {this.affinity = TextAffinity.downstream});

  final int offset;
  final TextAffinity affinity;

  TextNodePosition copyWith({int? offset, TextAffinity? affinity}) =>
      TextNodePosition(offset ?? this.offset, affinity: affinity ?? this.affinity);

  @override
  bool operator ==(Object other) =>
      other is TextNodePosition &&
      other.offset == offset &&
      other.affinity == affinity;

  @override
  int get hashCode => Object.hash(offset, affinity);

  @override
  String toString() => 'TextNodePosition($offset)';
}

/// A caret position relative to an atomic (non-text) node: either immediately
/// before it ([upstream]) or immediately after it ([downstream]).
@immutable
final class AtomicNodePosition extends NodePosition {
  const AtomicNodePosition.upstream() : upstream = true;
  const AtomicNodePosition.downstream() : upstream = false;

  final bool upstream;

  @override
  bool operator ==(Object other) =>
      other is AtomicNodePosition && other.upstream == upstream;

  @override
  int get hashCode => upstream.hashCode;

  @override
  String toString() =>
      'AtomicNodePosition(${upstream ? 'upstream' : 'downstream'})';
}

/// A position in the document: a node id plus a position within that node.
@immutable
final class DocumentPosition {
  const DocumentPosition({required this.nodeId, required this.nodePosition});

  final String nodeId;
  final NodePosition nodePosition;

  /// Convenience for text positions.
  static DocumentPosition text(String nodeId, int offset,
          {TextAffinity affinity = TextAffinity.downstream}) =>
      DocumentPosition(
        nodeId: nodeId,
        nodePosition: TextNodePosition(offset, affinity: affinity),
      );

  DocumentPosition copyWith({String? nodeId, NodePosition? nodePosition}) =>
      DocumentPosition(
        nodeId: nodeId ?? this.nodeId,
        nodePosition: nodePosition ?? this.nodePosition,
      );

  @override
  bool operator ==(Object other) =>
      other is DocumentPosition &&
      other.nodeId == nodeId &&
      other.nodePosition == nodePosition;

  @override
  int get hashCode => Object.hash(nodeId, nodePosition);

  @override
  String toString() => 'DocumentPosition($nodeId, $nodePosition)';
}
