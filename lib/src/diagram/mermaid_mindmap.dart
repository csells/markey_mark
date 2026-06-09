import 'package:flutter/material.dart';

/// A node in a mindmap tree.
class MindmapNode {
  MindmapNode(this.text, {this.depth = 0});
  final String text;
  final int depth;
  final List<MindmapNode> children = [];

  int get subtreeCount =>
      1 + children.fold(0, (s, c) => s + c.subtreeCount);
}

/// A parsed Mermaid `mindmap` diagram.
@immutable
class Mindmap {
  const Mindmap({required this.root});
  final MindmapNode root;

  /// Total number of nodes in the tree, including the root.
  int get nodeCount => root.subtreeCount;
}

final RegExp _firstLine = RegExp(r'^mindmap(\s|$)');

// Shape patterns, tried longest-delimiter first. An optional leading word id is
// stripped; the captured group is the displayed text.
final List<RegExp> _shapes = [
  RegExp(r'^\w*\(\((.+)\)\)$'), // ((circle))
  RegExp(r'^\w*\{\{(.+)\}\}$'), // {{hexagon}}
  RegExp(r'^\w*\)\)(.+)\(\($'), // ))bang((
  RegExp(r'^\w*\[(.+)\]$'), //    [square]
  RegExp(r'^\w*\((.+)\)$'), //    (round)
  RegExp(r'^\w*\)(.+)\($'), //    )cloud(
];

String _stripShape(String raw) {
  for (final re in _shapes) {
    final m = re.firstMatch(raw);
    if (m != null) return m.group(1)!.trim();
  }
  return raw;
}

int _indentOf(String line) {
  var n = 0;
  for (final ch in line.runes) {
    if (ch == 0x20) {
      n += 1;
    } else if (ch == 0x09) {
      n += 4; // treat a tab as four columns
    } else {
      break;
    }
  }
  return n;
}

/// Parses a Mermaid `mindmap` diagram, or returns null if [source] isn't one
/// (or has no root). Indentation defines the tree. Pure Dart — part of the
/// native, no-JS diagram engine.
Mindmap? parseMindmap(String source) {
  final raw = source.split('\n');
  // Find the `mindmap` header line.
  var i = 0;
  while (i < raw.length && raw[i].trim().isEmpty) {
    i++;
  }
  if (i >= raw.length || !_firstLine.hasMatch(raw[i].trim())) return null;

  MindmapNode? root;
  final stack = <MindmapNode>[];
  final indents = <int>[];

  for (var j = i + 1; j < raw.length; j++) {
    final line = raw[j];
    if (line.trim().isEmpty) continue;
    final indent = _indentOf(line);
    final text = _stripShape(line.trim());
    if (text.isEmpty) continue;

    if (root == null) {
      root = MindmapNode(text);
      stack.add(root);
      indents.add(indent);
      continue;
    }

    // Pop until we find the parent (strictly smaller indent).
    while (indents.length > 1 && indent <= indents.last) {
      stack.removeLast();
      indents.removeLast();
    }
    final node = MindmapNode(text, depth: stack.length);
    stack.last.children.add(node);
    stack.add(node);
    indents.add(indent);
  }

  if (root == null) return null;
  return Mindmap(root: root);
}

/// Renders a [Mindmap] natively as an indented tree with connector dots.
/// (A radial layout is a future enhancement; the tree view is fully readable
/// on every platform with no WebView/JS.)
class MermaidMindmapView extends StatelessWidget {
  const MermaidMindmapView({
    super.key,
    required this.mindmap,
    required this.textStyle,
    required this.lineColor,
    required this.fillColor,
  });
  final Mindmap mindmap;
  final TextStyle textStyle;
  final Color lineColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void visit(MindmapNode node, int depth) {
      rows.add(_row(node, depth));
      for (final child in node.children) {
        visit(child, depth + 1);
      }
    }

    visit(mindmap.root, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _row(MindmapNode node, int depth) {
    final isRoot = depth == 0;
    return Padding(
      padding: EdgeInsets.only(left: depth * 24.0, top: 2, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isRoot ? 10 : 6,
            height: isRoot ? 10 : 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: lineColor,
              shape: BoxShape.circle,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(isRoot ? 14 : 4),
              border: Border.all(color: lineColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              node.text,
              style: isRoot
                  ? textStyle.copyWith(fontWeight: FontWeight.bold)
                  : textStyle,
            ),
          ),
        ],
      ),
    );
  }
}
