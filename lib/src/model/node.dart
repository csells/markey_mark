import 'dart:math';

import 'package:meta/meta.dart';

import 'attributes.dart';
import 'delta.dart';

/// Generates stable, unique node ids.
///
/// Uses a monotonically increasing counter combined with random bits so ids
/// are unique within and across documents without pulling in a uuid
/// dependency. Ids are opaque; never parse them.
final class NodeIds {
  NodeIds._();
  static final Random _rng = Random();
  static int _counter = 0;

  static String next() {
    _counter++;
    final r = _rng.nextInt(1 << 32).toRadixString(36);
    return 'n${_counter.toRadixString(36)}_$r';
  }
}

/// Built-in block node type strings. Block type is stored as the node [Node.type]
/// (and, for headings, a `level` attribute) rather than as a subclass — so
/// "turn paragraph into heading" is an attribute edit, not a node swap.
abstract final class BlockType {
  static const String paragraph = 'paragraph';
  static const String heading = 'heading';
}

/// Base class for every node in the document.
///
/// Nodes are immutable value objects with a stable [id]; edits produce new node
/// instances (via [copyWith]) that replace the old one in the document. This
/// keeps the operation/undo model simple and predictable.
@immutable
sealed class Node {
  const Node({required this.id, required this.attributes});

  final String id;
  final Attributes attributes;

  String get type;

  Node copyWith({Attributes? attributes});
}

/// A block whose content is a single run of rich inline text (a [Delta]).
///
/// Covers paragraphs and headings in the vertical slice. The block kind is the
/// [type] string; heading level lives in `attributes['level']`.
@immutable
final class TextBlockNode extends Node {
  TextBlockNode({
    String? id,
    required this.type,
    required this.delta,
    Attributes? attributes,
  }) : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  @override
  final String type;

  final Delta delta;

  /// Heading level (1–6) for heading blocks; null otherwise.
  int? get level => attributes['level'] as int?;

  factory TextBlockNode.paragraph({String? id, Delta? delta}) => TextBlockNode(
        id: id,
        type: BlockType.paragraph,
        delta: delta ?? Delta.empty(),
      );

  factory TextBlockNode.heading({String? id, required int level, Delta? delta}) =>
      TextBlockNode(
        id: id,
        type: BlockType.heading,
        delta: delta ?? Delta.empty(),
        attributes: {'level': level},
      );

  TextBlockNode copyWithDelta(Delta newDelta) => TextBlockNode(
        id: id,
        type: type,
        delta: newDelta,
        attributes: attributes,
      );

  /// Returns a node of [newType] (with optional [level]) preserving id+delta.
  TextBlockNode asType(String newType, {int? level}) => TextBlockNode(
        id: id,
        type: newType,
        delta: delta,
        attributes: level != null ? {'level': level} : const {},
      );

  @override
  TextBlockNode copyWith({Attributes? attributes, Delta? delta}) => TextBlockNode(
        id: id,
        type: type,
        delta: delta ?? this.delta,
        attributes: attributes ?? this.attributes,
      );

  @override
  bool operator ==(Object other) =>
      other is TextBlockNode &&
      other.id == id &&
      other.type == type &&
      other.delta == delta &&
      attributesEqual(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(id, type, delta);

  @override
  String toString() =>
      'TextBlockNode($id, $type${level != null ? ' h$level' : ''}, $delta)';
}
