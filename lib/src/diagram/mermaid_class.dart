import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ClassRelationKind {
  inheritance, // <|--
  composition, // *--
  aggregation, // o--
  association, // -->
  dependency, // ..>
  realization, // ..|>
  link, // --
}

class ClassBox {
  ClassBox(this.name) : members = [];
  final String name;
  final List<String> members;
}

@immutable
class ClassRelation {
  const ClassRelation(this.from, this.to, this.kind, this.label);
  final String from;
  final String to;
  final ClassRelationKind kind;
  final String? label;
}

class ClassDiagram {
  ClassDiagram(this.classes, this.relations);
  final Map<String, ClassBox> classes; // insertion-ordered
  final List<ClassRelation> relations;
}

final RegExp _first = RegExp(r'^classDiagram(-v2)?(\s|$)');
final RegExp _relation = RegExp(
    r'^(\w+)\s*(<\|--|\.\.\|>|\*--|o--|-->|\.\.>|<\|\.\.|--)\s*(\w+)(?:\s*:\s*(.+))?$');
final RegExp _inlineMember = RegExp(r'^(\w+)\s*:\s*(.+)$');
final RegExp _classOpen = RegExp(r'^class\s+(\w+)\s*\{$');

ClassRelationKind _kind(String op) {
  switch (op) {
    case '<|--':
    case '<|..':
      return ClassRelationKind.inheritance;
    case '..|>':
      return ClassRelationKind.realization;
    case '*--':
      return ClassRelationKind.composition;
    case 'o--':
      return ClassRelationKind.aggregation;
    case '-->':
      return ClassRelationKind.association;
    case '..>':
      return ClassRelationKind.dependency;
    default:
      return ClassRelationKind.link;
  }
}

/// Parses a Mermaid `classDiagram`, or null if [source] isn't one (or empty).
/// Pure Dart — part of the native, no-JS diagram engine.
ClassDiagram? parseClassDiagram(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !_first.hasMatch(lines.first)) return null;

  final classes = <String, ClassBox>{};
  final relations = <ClassRelation>[];
  ClassBox box(String name) => classes.putIfAbsent(name, () => ClassBox(name));

  String? openClass;
  for (final line in lines.skip(1)) {
    if (openClass != null) {
      if (line == '}') {
        openClass = null;
      } else {
        box(openClass).members.add(line);
      }
      continue;
    }
    final open = _classOpen.firstMatch(line);
    if (open != null) {
      box(open.group(1)!);
      openClass = open.group(1)!;
      continue;
    }
    final rel = _relation.firstMatch(line);
    if (rel != null) {
      box(rel.group(1)!);
      box(rel.group(3)!);
      relations.add(ClassRelation(
          rel.group(1)!, rel.group(3)!, _kind(rel.group(2)!), rel.group(4)?.trim()));
      continue;
    }
    final mem = _inlineMember.firstMatch(line);
    if (mem != null) box(mem.group(1)!).members.add(mem.group(2)!.trim());
  }
  if (classes.isEmpty) return null;
  return ClassDiagram(classes, relations);
}

/// Renders a [ClassDiagram] natively: class boxes (name + members) in a wrapped
/// grid, connected by relationship lines.
class ClassDiagramView extends StatelessWidget {
  const ClassDiagramView({
    super.key,
    required this.diagram,
    required this.textStyle,
    required this.lineColor,
    required this.fillColor,
  });
  final ClassDiagram diagram;
  final TextStyle textStyle;
  final Color lineColor;
  final Color fillColor;

  static const double _boxW = 170;
  static const double _gap = 28;

  double _boxHeight(ClassBox b) => 30 + b.members.length * 18 + 8;

  Map<String, Rect> _layout() {
    final rects = <String, Rect>{};
    const perRow = 3;
    var i = 0;
    var rowTop = 0.0;
    var rowMaxH = 0.0;
    for (final box in diagram.classes.values) {
      final col = i % perRow;
      if (col == 0 && i > 0) {
        rowTop += rowMaxH + _gap;
        rowMaxH = 0;
      }
      final h = _boxHeight(box);
      rowMaxH = math.max(rowMaxH, h);
      rects[box.name] =
          Rect.fromLTWH(col * (_boxW + _gap), rowTop, _boxW, h);
      i++;
    }
    return rects;
  }

  @override
  Widget build(BuildContext context) {
    final rects = _layout();
    var maxX = 0.0, maxY = 0.0;
    for (final r in rects.values) {
      maxX = math.max(maxX, r.right);
      maxY = math.max(maxY, r.bottom);
    }
    return SizedBox(
      width: maxX + 4,
      height: maxY + 4,
      child: CustomPaint(
        painter:
            _ClassPainter(diagram, rects, textStyle, lineColor, fillColor),
      ),
    );
  }
}

class _ClassPainter extends CustomPainter {
  _ClassPainter(
      this.diagram, this.rects, this.textStyle, this.lineColor, this.fillColor);
  final ClassDiagram diagram;
  final Map<String, Rect> rects;
  final TextStyle textStyle;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()..color = fillColor;

    // Relationship lines (center-to-center, clipped at box edges).
    for (final rel in diagram.relations) {
      final a = rects[rel.from], b = rects[rel.to];
      if (a == null || b == null) continue;
      canvas.drawLine(a.center, b.center, stroke);
      _marker(canvas, b.center, a.center, rel.kind);
    }

    for (final box in diagram.classes.values) {
      final r = rects[box.name]!;
      canvas..drawRect(r, fill)..drawRect(r, stroke);
      // Header divider.
      canvas.drawLine(
          Offset(r.left, r.top + 26), Offset(r.right, r.top + 26), stroke);
      _text(canvas, box.name,
          Offset(r.left + 8, r.top + 6), bold: true, maxWidth: r.width - 16);
      for (var i = 0; i < box.members.length; i++) {
        _text(canvas, box.members[i],
            Offset(r.left + 8, r.top + 30 + i * 18.0), maxWidth: r.width - 16);
      }
    }
  }

  void _text(Canvas c, String s, Offset topLeft,
      {bool bold = false, double maxWidth = 150}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: bold
              ? textStyle.copyWith(fontWeight: FontWeight.bold)
              : textStyle.copyWith(fontSize: (textStyle.fontSize ?? 14) * 0.85)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(c, topLeft);
  }

  void _marker(Canvas c, Offset at, Offset from, ClassRelationKind kind) {
    final dir = (at - from);
    final len = dir.distance;
    if (len == 0) return;
    final u = dir / len;
    final base = at - u * 12;
    final n = Offset(-u.dy, u.dx) * 6;
    final p = Paint()..color = lineColor;
    switch (kind) {
      case ClassRelationKind.inheritance:
      case ClassRelationKind.realization:
        // hollow triangle
        final path = Path()
          ..moveTo(at.dx, at.dy)
          ..lineTo((base + n).dx, (base + n).dy)
          ..lineTo((base - n).dx, (base - n).dy)
          ..close();
        c.drawPath(path, Paint()..color = fillColor);
        c.drawPath(path, Paint()..color = lineColor..style = PaintingStyle.stroke);
      case ClassRelationKind.composition:
      case ClassRelationKind.aggregation:
        // diamond
        final tipTwo = at - u * 24;
        final path = Path()
          ..moveTo(at.dx, at.dy)
          ..lineTo((base + n).dx, (base + n).dy)
          ..lineTo(tipTwo.dx, tipTwo.dy)
          ..lineTo((base - n).dx, (base - n).dy)
          ..close();
        c.drawPath(path,
            kind == ClassRelationKind.composition ? p : (Paint()..color = fillColor));
        c.drawPath(path, Paint()..color = lineColor..style = PaintingStyle.stroke);
      default:
        // simple arrow
        final path = Path()
          ..moveTo(at.dx, at.dy)
          ..lineTo((base + n).dx, (base + n).dy)
          ..lineTo((base - n).dx, (base - n).dy)
          ..close();
        c.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(_ClassPainter old) => old.diagram != diagram;
}
