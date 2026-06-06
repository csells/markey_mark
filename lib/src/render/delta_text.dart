import 'package:flutter/widgets.dart';

import '../model/attributes.dart';
import '../model/delta.dart';
import '../model/node.dart';
import '../theme/editor_style.dart';

/// Resolves the base [TextStyle] for a text block (paragraph vs heading).
TextStyle baseStyleFor(TextBlockNode node, EditorStyle style) {
  if (node.type == BlockType.heading) {
    return style.headingStyle(node.level ?? 1);
  }
  return style.baseTextStyle;
}

/// Applies a run's inline [attributes] on top of [base].
TextStyle styleForAttributes(Attributes attrs, TextStyle base, EditorStyle es) {
  var s = base;
  if (attrs[InlineAttr.bold] == true) {
    s = s.copyWith(fontWeight: FontWeight.bold);
  }
  if (attrs[InlineAttr.italic] == true) {
    s = s.copyWith(fontStyle: FontStyle.italic);
  }
  if (attrs[InlineAttr.strike] == true) {
    s = s.copyWith(
      decoration: TextDecoration.combine([
        if (s.decoration != null && s.decoration != TextDecoration.none)
          s.decoration!,
        TextDecoration.lineThrough,
      ]),
    );
  }
  if (attrs[InlineAttr.code] == true) {
    s = s.merge(es.codeTextStyle).copyWith(fontSize: base.fontSize);
  }
  if (attrs.containsKey(InlineAttr.link)) {
    s = s.copyWith(
      color: es.linkColor,
      decoration: TextDecoration.underline,
    );
  }
  if (attrs.containsKey(InlineAttr.footnote)) {
    s = s.copyWith(
      color: es.linkColor,
      fontSize: (base.fontSize ?? 16) * 0.75,
      fontFeatures: const [FontFeature.superscripts()],
    );
  }
  return s;
}

/// Builds an [InlineSpan] for [delta] using [base] + [style].
///
/// Empty deltas yield a single zero-width span so the line still lays out (and
/// the caret has a place to sit).
InlineSpan deltaToTextSpan(Delta delta, TextStyle base, EditorStyle style) {
  if (delta.isEmpty) {
    return TextSpan(text: '', style: base);
  }
  return TextSpan(
    style: base,
    children: [
      for (final run in delta.runs)
        TextSpan(
          text: run.text,
          style: styleForAttributes(run.attributes, base, style),
        ),
    ],
  );
}
