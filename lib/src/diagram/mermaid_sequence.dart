import 'package:flutter/material.dart';

/// A single message between two participants in a sequence diagram.
@immutable
class SeqMessage {
  const SeqMessage({
    required this.from,
    required this.to,
    required this.text,
    required this.dashed,
  });
  final String from;
  final String to;
  final String text;
  final bool dashed;
}

/// A parsed Mermaid `sequenceDiagram`.
@immutable
class SequenceDiagram {
  const SequenceDiagram({
    required this.participants,
    required this.labels,
    required this.messages,
  });
  final List<String> participants;
  final Map<String, String> labels;
  final List<SeqMessage> messages;

  String labelFor(String id) => labels[id] ?? id;
}

final RegExp _first = RegExp(r'^sequenceDiagram(\s|$)');
final RegExp _participant =
    RegExp(r'^participant\s+(\w+)(?:\s+as\s+(.+))?$');
final RegExp _message =
    RegExp(r'^(\w+)\s*(-->>|->>|-->|->)\s*(\w+)\s*:\s*(.*)$');

/// Parses a Mermaid `sequenceDiagram`, or null if [source] isn't one (or has no
/// messages). Pure Dart — part of the native, no-JS diagram engine.
SequenceDiagram? parseSequence(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !_first.hasMatch(lines.first)) return null;

  final participants = <String>[];
  final labels = <String, String>{};
  final messages = <SeqMessage>[];

  void ensure(String id) {
    if (!participants.contains(id)) participants.add(id);
  }

  for (final line in lines.skip(1)) {
    final p = _participant.firstMatch(line);
    if (p != null) {
      ensure(p.group(1)!);
      if (p.group(2) != null) labels[p.group(1)!] = p.group(2)!.trim();
      continue;
    }
    final m = _message.firstMatch(line);
    if (m != null) {
      ensure(m.group(1)!);
      ensure(m.group(3)!);
      messages.add(SeqMessage(
        from: m.group(1)!,
        to: m.group(3)!,
        text: m.group(4)!.trim(),
        dashed: m.group(2)!.startsWith('--'),
      ));
    }
  }
  if (messages.isEmpty) return null;
  return SequenceDiagram(
      participants: participants, labels: labels, messages: messages);
}

/// Renders a [SequenceDiagram] natively (CustomPainter — lifelines + arrows).
class SequenceDiagramView extends StatelessWidget {
  const SequenceDiagramView({
    super.key,
    required this.diagram,
    required this.textStyle,
    required this.lineColor,
  });
  final SequenceDiagram diagram;
  final TextStyle textStyle;
  final Color lineColor;

  static const double _colWidth = 130;
  static const double _rowHeight = 44;
  static const double _headerHeight = 44;
  static const double _topPad = 8;

  @override
  Widget build(BuildContext context) {
    final width = diagram.participants.length * _colWidth;
    final height = _topPad +
        _headerHeight +
        diagram.messages.length * _rowHeight +
        _rowHeight;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SequencePainter(diagram, textStyle, lineColor),
      ),
    );
  }
}

class _SequencePainter extends CustomPainter {
  _SequencePainter(this.diagram, this.textStyle, this.lineColor);
  final SequenceDiagram diagram;
  final TextStyle textStyle;
  final Color lineColor;

  double _x(int i) =>
      SequenceDiagramView._colWidth * i + SequenceDiagramView._colWidth / 2;

  void _text(Canvas c, String s, Offset center, {double maxWidth = 120}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = lineColor.withValues(alpha: 0.08);

    final ids = diagram.participants;
    final topY = SequenceDiagramView._topPad;
    final boxH = 28.0;
    final lifelineTop = topY + boxH;
    final lifelineBottom = size.height - 6;

    // Participant boxes + lifelines.
    for (var i = 0; i < ids.length; i++) {
      final x = _x(i);
      final box = Rect.fromCenter(
          center: Offset(x, topY + boxH / 2), width: 108, height: boxH);
      final rrect = RRect.fromRectAndRadius(box, const Radius.circular(4));
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, line);
      _text(canvas, diagram.labelFor(ids[i]), box.center, maxWidth: 100);
      canvas.drawLine(
          Offset(x, lifelineTop), Offset(x, lifelineBottom), line);
    }

    // Messages.
    final arrow = Paint()
      ..color = lineColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (var m = 0; m < diagram.messages.length; m++) {
      final msg = diagram.messages[m];
      final fromI = ids.indexOf(msg.from);
      final toI = ids.indexOf(msg.to);
      if (fromI < 0 || toI < 0) continue;
      final y = lifelineTop +
          SequenceDiagramView._headerHeight +
          m * SequenceDiagramView._rowHeight;
      final x1 = _x(fromI);
      final x2 = _x(toI);
      _text(canvas, msg.text, Offset((x1 + x2) / 2, y - 12),
          maxWidth: (x2 - x1).abs().clamp(60, 240).toDouble());

      if (msg.dashed) {
        _dashedLine(canvas, Offset(x1, y), Offset(x2, y), arrow);
      } else {
        canvas.drawLine(Offset(x1, y), Offset(x2, y), arrow);
      }
      _arrowHead(canvas, Offset(x2, y), x2 >= x1, lineColor);
    }
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 5.0, gap = 3.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * (d + dash).clamp(0, total);
      c.drawLine(s, e, p);
      d += dash + gap;
    }
  }

  void _arrowHead(Canvas c, Offset tip, bool pointingRight, Color color) {
    final dx = pointingRight ? -7.0 : 7.0;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + dx, tip.dy - 4)
      ..lineTo(tip.dx + dx, tip.dy + 4)
      ..close();
    c.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SequencePainter old) =>
      old.diagram != diagram || old.lineColor != lineColor;
}
