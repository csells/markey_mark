import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class GanttTask {
  const GanttTask(this.name, this.section, this.durationDays);
  final String name;
  final String? section;
  final int durationDays;
}

@immutable
class Gantt {
  const Gantt({this.title, required this.tasks});
  final String? title;
  final List<GanttTask> tasks;
}

final RegExp _first = RegExp(r'^gantt(\s|$)');
final RegExp _title = RegExp(r'^title\s+(.+)$');
final RegExp _section = RegExp(r'^section\s+(.+)$');
final RegExp _duration = RegExp(r'(\d+)d\b');
const Set<String> _directives = {
  'dateFormat', 'axisFormat', 'excludes', 'todayMarker', 'tickInterval',
  'weekday',
};

/// Parses a Mermaid `gantt` chart (title, sections, and tasks with day
/// durations). Real dates/dependencies are simplified to sequential bars.
/// Pure Dart — part of the native, no-JS diagram engine.
Gantt? parseGantt(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !_first.hasMatch(lines.first)) return null;

  String? title;
  String? section;
  final tasks = <GanttTask>[];

  for (final line in lines.skip(1)) {
    final t = _title.firstMatch(line);
    if (t != null) {
      title = t.group(1)!.trim();
      continue;
    }
    final s = _section.firstMatch(line);
    if (s != null) {
      section = s.group(1)!.trim();
      continue;
    }
    if (_directives.any((d) => line.startsWith(d))) continue;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final name = line.substring(0, colon).trim();
    final rest = line.substring(colon + 1);
    final d = _duration.firstMatch(rest);
    tasks.add(GanttTask(name, section, d == null ? 1 : int.parse(d.group(1)!)));
  }
  if (tasks.isEmpty) return null;
  return Gantt(title: title, tasks: tasks);
}

/// Renders a [Gantt] natively: task rows with bars on a proportional time axis,
/// laid out sequentially (each task after the previous), grouped by section.
class GanttView extends StatelessWidget {
  const GanttView({
    super.key,
    required this.gantt,
    required this.textStyle,
    required this.barColor,
    required this.lineColor,
  });
  final Gantt gantt;
  final TextStyle textStyle;
  final Color barColor;
  final Color lineColor;

  static const double _nameW = 150;
  static const double _barAreaW = 460;
  static const double _rowH = 26;

  @override
  Widget build(BuildContext context) {
    final totalDays =
        gantt.tasks.fold<int>(0, (s, t) => s + t.durationDays).clamp(1, 100000);
    final rows = gantt.tasks.length +
        gantt.tasks.map((t) => t.section).toSet().length;
    final height = (gantt.title != null ? 28.0 : 0) + rows * _rowH + 8;
    return SizedBox(
      width: _nameW + _barAreaW + 8,
      height: height,
      child: CustomPaint(
        painter: _GanttPainter(
            gantt, totalDays.toDouble(), textStyle, barColor, lineColor),
      ),
    );
  }
}

class _GanttPainter extends CustomPainter {
  _GanttPainter(
      this.gantt, this.totalDays, this.textStyle, this.barColor, this.lineColor);
  final Gantt gantt;
  final double totalDays;
  final TextStyle textStyle;
  final Color barColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = GanttView._barAreaW / totalDays;
    var y = 0.0;
    if (gantt.title != null) {
      _text(canvas, gantt.title!, Offset(0, y), bold: true);
      y += 28;
    }
    var start = 0.0;
    String? lastSection;
    for (final task in gantt.tasks) {
      if (task.section != null && task.section != lastSection) {
        lastSection = task.section;
        _text(canvas, task.section!, Offset(0, y + 4), bold: true);
        y += GanttView._rowH;
      }
      _text(canvas, task.name, Offset(12, y + 4), maxWidth: GanttView._nameW - 16);
      final bx = GanttView._nameW + start * scale;
      final bw = math.max(2.0, task.durationDays * scale);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, y + 4, bw, GanttView._rowH - 8),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = barColor);
      start += task.durationDays;
      y += GanttView._rowH;
    }
  }

  void _text(Canvas c, String s, Offset at,
      {bool bold = false, double maxWidth = 140}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: bold ? textStyle.copyWith(fontWeight: FontWeight.bold) : textStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(c, at);
  }

  @override
  bool shouldRepaint(_GanttPainter old) => old.gantt != gantt;
}
