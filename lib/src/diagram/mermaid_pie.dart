import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One slice of a pie chart.
@immutable
class PieSlice {
  const PieSlice(this.label, this.value);
  final String label;
  final double value;
  double fraction(double total) => total == 0 ? 0 : value / total;
}

/// A parsed Mermaid `pie` diagram.
@immutable
class PieChart {
  const PieChart({this.title, required this.slices});
  final String? title;
  final List<PieSlice> slices;
  double get total => slices.fold(0, (s, e) => s + e.value);
}

final RegExp _firstLine = RegExp(r'^pie(\s|$)');
final RegExp _titleRe = RegExp(r'title\s+(.+)$');
final RegExp _sliceRe = RegExp(r'^"([^"]*)"\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*$');

/// Parses a Mermaid `pie` diagram, or returns null if [source] isn't one (or
/// has no slices). Pure Dart — part of the native, no-JS diagram engine.
PieChart? parsePie(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !_firstLine.hasMatch(lines.first)) return null;

  final titleMatch = _titleRe.firstMatch(lines.first);
  final title = titleMatch?.group(1)?.trim();

  final slices = <PieSlice>[];
  for (final line in lines.skip(1)) {
    final m = _sliceRe.firstMatch(line);
    if (m != null) slices.add(PieSlice(m.group(1)!, double.parse(m.group(2)!)));
  }
  if (slices.isEmpty) return null;
  return PieChart(title: title, slices: slices);
}

/// Default slice palette.
const List<Color> _palette = [
  Color(0xFF4E79A7), Color(0xFFF28E2B), Color(0xFFE15759), Color(0xFF76B7B2),
  Color(0xFF59A14F), Color(0xFFEDC948), Color(0xFFB07AA1), Color(0xFFFF9DA7),
  Color(0xFF9C755F), Color(0xFFBAB0AC),
];

Color sliceColor(int i) => _palette[i % _palette.length];

/// Renders a [PieChart] natively (CustomPainter + a legend).
class MermaidPieView extends StatelessWidget {
  const MermaidPieView({super.key, required this.chart, required this.textStyle});
  final PieChart chart;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chart.title != null && chart.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(chart.title!,
                style: textStyle.copyWith(fontWeight: FontWeight.bold)),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: CustomPaint(painter: _PiePainter(chart)),
            ),
            const SizedBox(width: 16),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < chart.slices.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 12, height: 12, color: sliceColor(i)),
                        const SizedBox(width: 6),
                        Text(
                          '${chart.slices[i].label} '
                          '(${(chart.slices[i].fraction(chart.total) * 100).toStringAsFixed(0)}%)',
                          style: textStyle,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.chart);
  final PieChart chart;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2; // 12 o'clock
    final total = chart.total;
    for (var i = 0; i < chart.slices.length; i++) {
      final sweep = chart.slices[i].fraction(total) * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = sliceColor(i));
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.chart != chart;
}
