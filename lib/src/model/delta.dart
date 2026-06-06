import 'package:meta/meta.dart';

import 'attributes.dart';

/// A single run of text carrying uniform inline [attributes].
///
/// This is the storage form of inline content. A [Delta] is an ordered list of
/// these runs, which is isomorphic to super_editor's flattened
/// `MultiAttributionSpan` list — one uniform-style run per span — so walking
/// the runs in order gives order-stable rendering and serialization.
@immutable
final class TextRun {
  TextRun(this.text, [Attributes? attributes])
      : attributes = normalizeAttributes(attributes);

  final String text;
  final Attributes attributes;

  int get length => text.length;
  bool get isEmpty => text.isEmpty;

  TextRun copyWith({String? text, Attributes? attributes}) =>
      TextRun(text ?? this.text, attributes ?? this.attributes);

  @override
  bool operator ==(Object other) =>
      other is TextRun &&
      other.text == text &&
      attributesEqual(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(text, Object.hashAllUnordered(attributes.keys));

  @override
  String toString() =>
      'TextRun(${_escape(text)}${attributes.isEmpty ? '' : ', $attributes'})';

  static String _escape(String s) =>
      "'${s.replaceAll('\n', r'\n')}'";
}

/// An ordered sequence of styled text [runs] — the rich inline content of a
/// text block.
///
/// The stored form contains only insert runs. Range edits ([insert],
/// [delete], [format], [slice]) produce new normalized deltas (runs are
/// immutable; the delta is treated as a persistent value). Adjacent runs with
/// equal attributes are merged by [normalized] so the representation stays
/// canonical — this is what keeps Markdown serialization stable and avoids
/// artifacts like `**a****b**`.
@immutable
final class Delta {
  const Delta._(this.runs);

  factory Delta(List<TextRun> runs) => Delta._(List.unmodifiable(runs)).normalized;

  /// An empty delta.
  factory Delta.empty() => const Delta._([]);

  /// A delta containing a single plain-text run.
  factory Delta.text(String text, [Attributes? attributes]) =>
      text.isEmpty ? Delta.empty() : Delta([TextRun(text, attributes)]);

  final List<TextRun> runs;

  int get length {
    var n = 0;
    for (final r in runs) {
      n += r.length;
    }
    return n;
  }

  bool get isEmpty => runs.isEmpty;
  bool get isNotEmpty => runs.isNotEmpty;

  String toPlainText() {
    final b = StringBuffer();
    for (final r in runs) {
      b.write(r.text);
    }
    return b.toString();
  }

  /// Returns a normalized copy: empty runs dropped, adjacent runs with equal
  /// attributes merged.
  Delta get normalized {
    if (runs.isEmpty) return this;
    final out = <TextRun>[];
    for (final run in runs) {
      if (run.isEmpty) continue;
      if (out.isNotEmpty && attributesEqual(out.last.attributes, run.attributes)) {
        out[out.length - 1] = TextRun(out.last.text + run.text, run.attributes);
      } else {
        out.add(run);
      }
    }
    return Delta._(List.unmodifiable(out));
  }

  /// The attributes inherited when typing at character [index].
  ///
  /// Uses "preceding character" semantics: typing at [index] inherits the
  /// attributes of the character at `index - 1`, so continuing to type after a
  /// bold word stays bold. At index 0 there is no preceding character, so the
  /// result is the empty attribute set.
  Attributes attributesAt(int index) {
    if (runs.isEmpty || index <= 0) return const {};
    final probe = (index - 1).clamp(0, length - 1);
    var pos = 0;
    for (final run in runs) {
      if (probe < pos + run.length) return run.attributes;
      pos += run.length;
    }
    return runs.last.attributes;
  }

  /// Returns the sub-delta covering `[start, end)`.
  Delta slice(int start, [int? end]) {
    final to = end ?? length;
    if (start < 0 || to > length || start > to) {
      throw RangeError('slice($start, $to) out of range for length $length');
    }
    if (start == to) return Delta.empty();
    final out = <TextRun>[];
    var pos = 0;
    for (final run in runs) {
      final runStart = pos;
      final runEnd = pos + run.length;
      if (runEnd > start && runStart < to) {
        final s = (start - runStart).clamp(0, run.length);
        final e = (to - runStart).clamp(0, run.length);
        out.add(TextRun(run.text.substring(s, e), run.attributes));
      }
      pos = runEnd;
      if (pos >= to) break;
    }
    return Delta._(List.unmodifiable(out)).normalized;
  }

  /// Concatenates this delta with [other].
  Delta concat(Delta other) => Delta._([...runs, ...other.runs]).normalized;

  /// Inserts [text] (with [attributes]) at character [index].
  Delta insert(int index, String text, [Attributes? attributes]) {
    if (text.isEmpty) return this;
    if (index < 0 || index > length) {
      throw RangeError('insert index $index out of range for length $length');
    }
    return slice(0, index)
        .concat(Delta.text(text, attributes))
        .concat(slice(index, length));
  }

  /// Deletes the characters in `[start, end)`.
  Delta delete(int start, int end) {
    if (start == end) return this;
    return slice(0, start).concat(slice(end, length));
  }

  /// Applies [attributes] over `[start, end)`. A value of `false`/`null`
  /// removes that key.
  Delta format(int start, int end, Attributes attributes) {
    if (start == end) return this;
    final before = slice(0, start);
    final middle = slice(start, end);
    final after = slice(end, length);
    final reformatted = <TextRun>[];
    for (final run in middle.runs) {
      final merged = <String, Object?>{...run.attributes};
      for (final entry in attributes.entries) {
        if (entry.value == null || entry.value == false) {
          merged.remove(entry.key);
        } else {
          merged[entry.key] = entry.value;
        }
      }
      reformatted.add(TextRun(run.text, merged));
    }
    return before
        .concat(Delta._(List.unmodifiable(reformatted)))
        .concat(after)
        .normalized;
  }

  /// True if every character in `[start, end)` carries [key] == true.
  bool isFormatted(int start, int end, String key) {
    if (start >= end) return false;
    final middle = slice(start, end);
    if (middle.isEmpty) return false;
    for (final run in middle.runs) {
      if (run.attributes[key] != true) return false;
    }
    return true;
  }

  List<Map<String, Object?>> toJson() => [
        for (final r in runs)
          {
            'insert': r.text,
            if (r.attributes.isNotEmpty) 'attributes': r.attributes,
          }
      ];

  factory Delta.fromJson(List<dynamic> json) => Delta([
        for (final op in json)
          TextRun(
            (op as Map)['insert'] as String,
            (op['attributes'] as Map?)?.cast<String, Object?>(),
          )
      ]);

  @override
  bool operator ==(Object other) {
    if (other is! Delta) return false;
    if (other.runs.length != runs.length) return false;
    for (var i = 0; i < runs.length; i++) {
      if (runs[i] != other.runs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(runs);

  @override
  String toString() => 'Delta(${runs.join(', ')})';
}
