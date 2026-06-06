import 'package:flutter/material.dart';

/// One time period on a timeline: a label and the events recorded against it.
@immutable
class TimelinePeriod {
  const TimelinePeriod({required this.label, required this.events});
  final String label;
  final List<String> events;
}

/// A named group of [TimelinePeriod]s (a Mermaid `section`).
@immutable
class TimelineSection {
  const TimelineSection({required this.name, required this.periods});
  final String name;
  final List<TimelinePeriod> periods;
}

/// A parsed Mermaid `timeline` diagram.
@immutable
class Timeline {
  const Timeline({this.title, required this.sections});
  final String? title;
  final List<TimelineSection> sections;

  /// All periods across every section, in document order.
  List<TimelinePeriod> get periods =>
      [for (final s in sections) ...s.periods];
}

final RegExp _firstLine = RegExp(r'^timeline(\s|$)');
final RegExp _titleRe = RegExp(r'^title\s+(.+)$');
final RegExp _sectionRe = RegExp(r'^section\s+(.+)$');

/// Parses a Mermaid `timeline` diagram, or returns null if [source] isn't one
/// (or has no periods). Pure Dart — part of the native, no-JS diagram engine.
Timeline? parseTimeline(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !_firstLine.hasMatch(lines.first)) return null;

  String? title;
  final sections = <TimelineSection>[];
  String currentName = '';
  var currentPeriods = <TimelinePeriod>[];

  void flush() {
    if (currentPeriods.isNotEmpty || currentName.isNotEmpty) {
      sections.add(TimelineSection(name: currentName, periods: currentPeriods));
    }
  }

  for (final line in lines.skip(1)) {
    final titleM = _titleRe.firstMatch(line);
    if (titleM != null) {
      title = titleM.group(1)!.trim();
      continue;
    }
    final sectionM = _sectionRe.firstMatch(line);
    if (sectionM != null) {
      flush();
      currentName = sectionM.group(1)!.trim();
      currentPeriods = <TimelinePeriod>[];
      continue;
    }
    if (!line.contains(':')) continue;
    final parts = line.split(':').map((p) => p.trim()).toList();
    final label = parts.first;
    if (label.isEmpty) continue;
    final events = parts.skip(1).where((e) => e.isNotEmpty).toList();
    currentPeriods.add(TimelinePeriod(label: label, events: events));
  }
  flush();

  if (sections.every((s) => s.periods.isEmpty)) return null;
  return Timeline(title: title, sections: sections);
}

/// Renders a [Timeline] natively: periods laid out left-to-right along an axis,
/// each with its events stacked beneath, grouped into labelled sections.
class MermaidTimelineView extends StatelessWidget {
  const MermaidTimelineView({
    super.key,
    required this.timeline,
    required this.textStyle,
    required this.lineColor,
    required this.fillColor,
  });
  final Timeline timeline;
  final TextStyle textStyle;
  final Color lineColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    final boldStyle = textStyle.copyWith(fontWeight: FontWeight.bold);
    final hasSections =
        timeline.sections.any((s) => s.name.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (timeline.title != null && timeline.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(timeline.title!, style: boldStyle),
          ),
        for (final section in timeline.sections) ...[
          if (hasSections && section.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text(section.name, style: boldStyle),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final period in section.periods)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: fillColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: lineColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(period.label, style: boldStyle),
                        ),
                        const SizedBox(height: 4),
                        for (final event in period.events)
                          Padding(
                            padding: const EdgeInsets.only(top: 2, left: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, right: 4),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: lineColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                Expanded(
                                    child: Text(event, style: textStyle)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
