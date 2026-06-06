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
  static const String bulletedListItem = 'bulleted_list_item';
  static const String numberedListItem = 'numbered_list_item';
  static const String todoListItem = 'todo_list_item';
  static const String quote = 'quote';
  static const String codeBlock = 'code_block';
  static const String horizontalRule = 'horizontal_rule';
  static const String image = 'image';
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

  factory TextBlockNode.bullet({String? id, Delta? delta}) => TextBlockNode(
        id: id,
        type: BlockType.bulletedListItem,
        delta: delta ?? Delta.empty(),
      );

  factory TextBlockNode.numbered({String? id, required int number, Delta? delta}) =>
      TextBlockNode(
        id: id,
        type: BlockType.numberedListItem,
        delta: delta ?? Delta.empty(),
        attributes: {'number': number},
      );

  factory TextBlockNode.todo({String? id, bool checked = false, Delta? delta}) =>
      TextBlockNode(
        id: id,
        type: BlockType.todoListItem,
        delta: delta ?? Delta.empty(),
        attributes: {'checked': checked},
      );

  factory TextBlockNode.quote({String? id, Delta? delta}) => TextBlockNode(
        id: id,
        type: BlockType.quote,
        delta: delta ?? Delta.empty(),
      );

  /// Ordered-list number (for [BlockType.numberedListItem]); null otherwise.
  int? get number => attributes['number'] as int?;

  /// Task checkbox state (for [BlockType.todoListItem]); null for other types.
  ///
  /// Derived from the presence of a truthy `checked` attribute, so an unchecked
  /// task (whose `false` is dropped by attribute normalization) still reports
  /// `false` rather than null.
  bool? get checked =>
      type == BlockType.todoListItem ? attributes['checked'] == true : null;

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

/// A fenced/indented code block: literal [code] text with an optional [language]
/// for syntax highlighting. Its content is plain text, not a [Delta].
@immutable
final class CodeBlockNode extends Node {
  CodeBlockNode({
    String? id,
    required this.code,
    this.language,
    Attributes? attributes,
  }) : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  final String code;
  final String? language;

  @override
  String get type => BlockType.codeBlock;

  CodeBlockNode copyWithCode(String newCode, {String? language}) => CodeBlockNode(
        id: id,
        code: newCode,
        language: language ?? this.language,
        attributes: attributes,
      );

  @override
  Node copyWith({Attributes? attributes}) => CodeBlockNode(
        id: id,
        code: code,
        language: language,
        attributes: attributes ?? this.attributes,
      );

  @override
  bool operator ==(Object other) =>
      other is CodeBlockNode &&
      other.id == id &&
      other.code == code &&
      other.language == language;

  @override
  int get hashCode => Object.hash(id, code, language);

  @override
  String toString() => 'CodeBlockNode($id, ${language ?? 'plain'})';
}

/// An image block: `![alt](url "title")`. Atomic.
@immutable
final class ImageNode extends Node {
  ImageNode({
    String? id,
    required this.url,
    this.alt,
    this.title,
    Attributes? attributes,
  }) : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  final String url;
  final String? alt;
  final String? title;

  @override
  String get type => BlockType.image;

  @override
  Node copyWith({Attributes? attributes}) => ImageNode(
        id: id,
        url: url,
        alt: alt,
        title: title,
        attributes: attributes ?? this.attributes,
      );

  @override
  bool operator ==(Object other) =>
      other is ImageNode &&
      other.id == id &&
      other.url == url &&
      other.alt == alt &&
      other.title == title;

  @override
  int get hashCode => Object.hash(id, url, alt, title);

  @override
  String toString() => 'ImageNode($id, $url)';
}

/// A thematic break (`---`). An atomic, contentless block.
@immutable
final class HorizontalRuleNode extends Node {
  HorizontalRuleNode({String? id, Attributes? attributes})
      : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  @override
  String get type => BlockType.horizontalRule;

  @override
  Node copyWith({Attributes? attributes}) =>
      HorizontalRuleNode(id: id, attributes: attributes ?? this.attributes);

  @override
  bool operator ==(Object other) =>
      other is HorizontalRuleNode && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'HorizontalRuleNode($id)';
}
