import 'dart:math';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:meta/meta.dart';

import 'attributes.dart';
import 'delta.dart';

/// Generates stable, unique node ids.
///
/// Uses a monotonically increasing counter combined with random bits so ids
/// are unique within and across documents without pulling in a uuid
/// dependency. Ids are opaque; never parse them.
/// Generates collision-free node ids for one *site* (a process/peer). Ids are
/// `<site>_<counter>`: the per-site random prefix guarantees that two peers (or
/// two documents) never mint the same id — the precondition for collaboration
/// convergence and stable references (§13.4 / ADR-008). Ids are unique and
/// stable within a session.
class NodeIdGenerator {
  NodeIdGenerator({String? site}) : site = site ?? _randomSite();

  final String site;
  int _counter = 0;

  String next() => '${site}_${(_counter++).toRadixString(36)}';

  static final Random _rng = Random();
  // 2^32 written as a literal, not `1 << 32`: on the web (JS bitwise ops are
  // 32-bit) `1 << 32` wraps to 0, and nextInt(0) throws. The literal is exact in
  // a JS double and is the max nextInt accepts (0 < max <= 2^32).
  static const int _siteBits = 0x100000000;
  static String _randomSite() =>
      _rng.nextInt(_siteBits).toRadixString(36).padLeft(7, '0');
}

/// The default, process-wide id generator (one site per process).
final class NodeIds {
  NodeIds._();
  static final NodeIdGenerator _default = NodeIdGenerator();
  static String next() => _default.next();
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
  static const String mathBlock = 'math_block';
  static const String table = 'table';
  static const String mermaid = 'mermaid';
  static const String footnoteDef = 'footnote_def';
  static const String frontMatter = 'front_matter';
  static const String definitionTerm = 'definition_term';
  static const String definitionDesc = 'definition_desc';
  static const String htmlBlock = 'html_block';
}

/// Column alignment for a GFM table.
enum TableAlign { none, left, center, right }

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

  factory TextBlockNode.bullet({String? id, Delta? delta, int indent = 0}) =>
      TextBlockNode(
        id: id,
        type: BlockType.bulletedListItem,
        delta: delta ?? Delta.empty(),
        attributes: {if (indent > 0) 'indent': indent},
      );

  factory TextBlockNode.numbered(
          {String? id, required int number, Delta? delta, int indent = 0}) =>
      TextBlockNode(
        id: id,
        type: BlockType.numberedListItem,
        delta: delta ?? Delta.empty(),
        attributes: {'number': number, if (indent > 0) 'indent': indent},
      );

  factory TextBlockNode.todo(
          {String? id, bool checked = false, Delta? delta, int indent = 0}) =>
      TextBlockNode(
        id: id,
        type: BlockType.todoListItem,
        delta: delta ?? Delta.empty(),
        attributes: {'checked': checked, if (indent > 0) 'indent': indent},
      );

  /// List-item indentation depth (0 = top level).
  int get indent => attributes['indent'] as int? ?? 0;

  factory TextBlockNode.quote(
          {String? id, Delta? delta, int indent = 0, String? callout}) =>
      TextBlockNode(
        id: id,
        type: BlockType.quote,
        delta: delta ?? Delta.empty(),
        attributes: {
          if (indent > 0) 'indent': indent,
          if (callout != null) 'callout': callout,
        },
      );

  /// For [BlockType.quote] blocks that are a GitHub-style alert/callout, the
  /// kind: one of `note`, `tip`, `important`, `warning`, `caution`. Null for an
  /// ordinary block quote.
  String? get callout => attributes['callout'] as String?;

  factory TextBlockNode.definitionTerm({String? id, Delta? delta}) =>
      TextBlockNode(
          id: id, type: BlockType.definitionTerm, delta: delta ?? Delta.empty());

  factory TextBlockNode.definitionDesc({String? id, Delta? delta}) =>
      TextBlockNode(
          id: id, type: BlockType.definitionDesc, delta: delta ?? Delta.empty());

  factory TextBlockNode.footnoteDef(
          {String? id, required String label, Delta? delta}) =>
      TextBlockNode(
        id: id,
        type: BlockType.footnoteDef,
        delta: delta ?? Delta.empty(),
        attributes: {'label': label},
      );

  /// Footnote label (for [BlockType.footnoteDef]); null otherwise.
  String? get footnoteLabel => attributes['label'] as String?;

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

/// A raw HTML block, preserved verbatim so it round-trips losslessly (the model
/// doesn't interpret HTML — per the no-WebView/no-JS constraint it's shown as
/// source — but it is never mangled or re-escaped).
@immutable
final class HtmlBlockNode extends Node {
  HtmlBlockNode({String? id, required this.html, Attributes? attributes})
      : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  final String html;

  @override
  String get type => BlockType.htmlBlock;

  @override
  Node copyWith({Attributes? attributes}) =>
      HtmlBlockNode(id: id, html: html, attributes: attributes ?? this.attributes);

  @override
  bool operator ==(Object other) =>
      other is HtmlBlockNode && other.id == id && other.html == html;

  @override
  int get hashCode => Object.hash(id, html);

  @override
  String toString() => 'HtmlBlockNode($id)';
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

/// A Mermaid diagram (a ` ```mermaid ` fenced block) holding diagram [source].
/// Rendered by a pluggable native diagram engine; degrades to a source card.
@immutable
final class MermaidNode extends Node {
  MermaidNode({String? id, required this.source, Attributes? attributes})
      : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  final String source;

  @override
  String get type => BlockType.mermaid;

  @override
  Node copyWith({Attributes? attributes}) =>
      MermaidNode(id: id, source: source, attributes: attributes ?? this.attributes);

  @override
  bool operator ==(Object other) =>
      other is MermaidNode && other.id == id && other.source == source;

  @override
  int get hashCode => Object.hash(id, source);

  @override
  String toString() => 'MermaidNode($id)';
}

/// A display math block: `$$ … $$` holding LaTeX [tex]. Atomic.
@immutable
final class MathBlockNode extends Node {
  MathBlockNode({String? id, required this.tex, Attributes? attributes})
      : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  final String tex;

  @override
  String get type => BlockType.mathBlock;

  @override
  Node copyWith({Attributes? attributes}) =>
      MathBlockNode(id: id, tex: tex, attributes: attributes ?? this.attributes);

  @override
  bool operator ==(Object other) =>
      other is MathBlockNode && other.id == id && other.tex == tex;

  @override
  int get hashCode => Object.hash(id, tex);

  @override
  String toString() => 'MathBlockNode($id)';
}

/// Leading YAML front matter (`--- … ---` at the document start), passed
/// through verbatim as [yaml]. Atomic.
@immutable
final class FrontMatterNode extends Node {
  FrontMatterNode({String? id, required this.yaml, Attributes? attributes})
      : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  final String yaml;

  @override
  String get type => BlockType.frontMatter;

  @override
  Node copyWith({Attributes? attributes}) =>
      FrontMatterNode(id: id, yaml: yaml, attributes: attributes ?? this.attributes);

  @override
  bool operator ==(Object other) =>
      other is FrontMatterNode && other.id == id && other.yaml == yaml;

  @override
  int get hashCode => Object.hash(id, yaml);

  @override
  String toString() => 'FrontMatterNode($id)';
}

/// A plugin-defined block: an open extension point (§13.5 / ADR-008) so the
/// block set isn't a closed `sealed`+`switch`. Carries a [blockType] string and
/// arbitrary [data]; a registered `BlockSpec` decides how to render/serialize it.
@immutable
final class CustomBlockNode extends Node {
  CustomBlockNode({
    String? id,
    required this.blockType,
    this.data = const {},
    Attributes? attributes,
  }) : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  final String blockType;
  final Map<String, Object?> data;

  @override
  String get type => blockType;

  @override
  Node copyWith({Attributes? attributes}) => CustomBlockNode(
        id: id,
        blockType: blockType,
        data: data,
        attributes: attributes ?? this.attributes,
      );

  @override
  bool operator ==(Object other) =>
      other is CustomBlockNode &&
      other.id == id &&
      other.blockType == blockType &&
      mapEquals(other.data, data);

  @override
  int get hashCode => Object.hash(id, blockType, Object.hashAll(data.values));

  @override
  String toString() => 'CustomBlockNode($id, $blockType)';
}

/// A GFM table: [rows] of cells (each a [Delta]), row 0 being the header, plus
/// per-column [alignments]. Atomic at the document level; cells are edited
/// in place by the table component.
@immutable
final class TableNode extends Node {
  TableNode({
    String? id,
    required this.rows,
    required this.alignments,
    Attributes? attributes,
  }) : super(id: id ?? NodeIds.next(), attributes: normalizeAttributes(attributes));

  /// `rows[r][c]` is the cell content; `rows[0]` is the header row.
  final List<List<Delta>> rows;
  final List<TableAlign> alignments;

  @override
  String get type => BlockType.table;

  int get rowCount => rows.length;
  int get columnCount => alignments.length;

  String cellText(int row, int col) => rows[row][col].toPlainText();

  /// Returns a copy with cell (row,col) replaced by [delta].
  TableNode withCell(int row, int col, Delta delta) {
    final newRows = [
      for (var r = 0; r < rows.length; r++)
        [
          for (var c = 0; c < rows[r].length; c++)
            (r == row && c == col) ? delta : rows[r][c]
        ]
    ];
    return TableNode(id: id, rows: newRows, alignments: alignments, attributes: attributes);
  }

  /// Returns a copy with an empty row appended.
  TableNode withAppendedRow() {
    final newRow = [for (var c = 0; c < columnCount; c++) Delta.empty()];
    return TableNode(
        id: id, rows: [...rows, newRow], alignments: alignments, attributes: attributes);
  }

  /// Returns a copy with an empty (left-aligned-by-default) column appended.
  TableNode withAppendedColumn() {
    final newRows = [
      for (final r in rows) [...r, Delta.empty()]
    ];
    return TableNode(
      id: id,
      rows: newRows,
      alignments: [...alignments, TableAlign.none],
      attributes: attributes,
    );
  }

  @override
  Node copyWith({Attributes? attributes}) => TableNode(
        id: id,
        rows: rows,
        alignments: alignments,
        attributes: attributes ?? this.attributes,
      );

  @override
  bool operator ==(Object other) =>
      other is TableNode &&
      other.id == id &&
      _rowsEqual(other.rows, rows) &&
      _listEq(other.alignments, alignments);

  static bool _listEq<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _rowsEqual(List<List<Delta>> a, List<List<Delta>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_listEq(a[i], b[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, rowCount, columnCount);

  @override
  String toString() => 'TableNode($id, ${rowCount}x$columnCount)';
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
