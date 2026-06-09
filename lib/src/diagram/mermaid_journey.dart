import 'package:flutter/material.dart';

/// One task in a user-journey diagram: a name, a satisfaction score (1–5) and
/// the actors involved.
@immutable
class JourneyTask {
  const JourneyTask({
    required this.name,
    required this.score,
    required this.actors,
  });
  final String name;
  final int score;
  final List<String> actors;
}

/// A titled group of [JourneyTask]s.
@immutable
class JourneySection {
  const JourneySection({required this.name, required this.tasks});
  final String name;
  final List<JourneyTask> tasks;
}

/// A parsed Mermaid `journey` diagram.
@immutable
class Journey {
  const Journey({this.title, required this.sections, required this.actors});
  final String? title;
  final List<JourneySection> sections;

  /// Distinct actors across all tasks, in first-seen order.
  final List<String> actors;

  Iterable<JourneyTask> get allTasks =>
      sections.expand((s) => s.tasks);
}

final RegExp _firstLine = RegExp(r'^journey(\s|$)');
final RegExp _titleRe = RegExp(r'^title\s+(.+)$');
final RegExp _sectionRe = RegExp(r'^section\s+(.+)$');
final RegExp _taskRe =
    RegExp(r'^(.+?)\s*:\s*([0-9]+)\s*:\s*(.+)$');

/// Parses a Mermaid `journey` diagram, or returns null if [source] isn't one
/// (or has no tasks). Pure Dart — part of the native, no-JS diagram engine.
Journey? parseJourney(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !_firstLine.hasMatch(lines.first)) return null;

  String? title;
  final sections = <JourneySection>[];
  final actorOrder = <String>[];
  final actorSeen = <String>{};
  List<JourneyTask>? current;

  void closeSection(String name) {
    sections.add(JourneySection(name: name, tasks: current ?? []));
  }

  String? pendingSection;
  for (final line in lines.skip(1)) {
    final titleM = _titleRe.firstMatch(line);
    if (titleM != null) {
      title = titleM.group(1)!.trim();
      continue;
    }
    final sectionM = _sectionRe.firstMatch(line);
    if (sectionM != null) {
      if (pendingSection != null) closeSection(pendingSection);
      pendingSection = sectionM.group(1)!.trim();
      current = <JourneyTask>[];
      continue;
    }
    final taskM = _taskRe.firstMatch(line);
    if (taskM != null) {
      // Tasks before any `section` start an implicit untitled section.
      if (pendingSection == null) {
        pendingSection = '';
        current = <JourneyTask>[];
      }
      final actors = taskM
          .group(3)!
          .split(',')
          .map((a) => a.trim())
          .where((a) => a.isNotEmpty)
          .toList();
      for (final a in actors) {
        if (actorSeen.add(a)) actorOrder.add(a);
      }
      final score = int.parse(taskM.group(2)!).clamp(1, 5);
      current!.add(JourneyTask(
        name: taskM.group(1)!.trim(),
        score: score,
        actors: actors,
      ));
    }
  }
  if (pendingSection != null) closeSection(pendingSection);

  if (sections.every((s) => s.tasks.isEmpty)) return null;
  return Journey(title: title, sections: sections, actors: actorOrder);
}

/// Default actor palette (shared visual language with the pie palette).
const List<Color> _palette = [
  Color(0xFF4E79A7), Color(0xFFF28E2B), Color(0xFFE15759), Color(0xFF76B7B2),
  Color(0xFF59A14F), Color(0xFFEDC948), Color(0xFFB07AA1), Color(0xFFFF9DA7),
  Color(0xFF9C755F), Color(0xFFBAB0AC),
];

/// Renders a [Journey] natively: tasks laid out left-to-right with a
/// satisfaction score (1–5) shown as a vertical position, grouped into
/// labelled sections, plus an actor legend. CustomPainter — no WebView/JS.
class MermaidJourneyView extends StatelessWidget {
  const MermaidJourneyView({
    super.key,
    required this.journey,
    required this.textStyle,
    required this.lineColor,
  });
  final Journey journey;
  final TextStyle textStyle;
  final Color lineColor;

  Color _actorColor(String actor) {
    final i = journey.actors.indexOf(actor);
    return _palette[(i < 0 ? 0 : i) % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final tasks = journey.allTasks.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (journey.title != null && journey.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(journey.title!,
                style: textStyle.copyWith(fontWeight: FontWeight.bold)),
          ),
        SizedBox(
          width: (tasks.length * 96).toDouble().clamp(120, double.infinity),
          height: 180,
          child: CustomPaint(
            painter: _JourneyPainter(
              journey: journey,
              textStyle: textStyle,
              lineColor: lineColor,
              actorColor: _actorColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final actor in journey.actors)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 12, color: _actorColor(actor)),
                  const SizedBox(width: 6),
                  Text(actor, style: textStyle),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _JourneyPainter extends CustomPainter {
  _JourneyPainter({
    required this.journey,
    required this.textStyle,
    required this.lineColor,
    required this.actorColor,
  });
  final Journey journey;
  final TextStyle textStyle;
  final Color lineColor;
  final Color Function(String) actorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final tasks = journey.allTasks.toList();
    if (tasks.isEmpty) return;
    const topPad = 16.0;
    const bottomPad = 40.0;
    final plotHeight = size.height - topPad - bottomPad;
    final step = size.width / tasks.length;

    double xOf(int i) => step * i + step / 2;
    // Score 1 (low) at bottom, 5 (high) at top.
    double yOf(int score) =>
        topPad + plotHeight * (1 - (score - 1) / 4);

    // Connecting line through task points.
    final path = Path();
    for (var i = 0; i < tasks.length; i++) {
      final p = Offset(xOf(i), yOf(tasks[i].score));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final center = Offset(xOf(i), yOf(task.score));
      final color = task.actors.isEmpty
          ? lineColor
          : actorColor(task.actors.first);
      canvas.drawCircle(center, 10, Paint()..color = color);
      _label(canvas, '${task.score}', center,
          textStyle.copyWith(color: Colors.white, fontSize: 11),
          anchor: _Anchor.center);
      _label(canvas, task.name, Offset(center.dx, size.height - bottomPad + 4),
          textStyle.copyWith(fontSize: (textStyle.fontSize ?? 14) * 0.85),
          anchor: _Anchor.topCenter, maxWidth: step);
    }
  }

  void _label(Canvas canvas, String text, Offset at, TextStyle style,
      {required _Anchor anchor, double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final offset = switch (anchor) {
      _Anchor.center => at - Offset(tp.width / 2, tp.height / 2),
      _Anchor.topCenter => at - Offset(tp.width / 2, 0),
    };
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_JourneyPainter old) => old.journey != journey;
}

enum _Anchor { center, topCenter }
