import 'package:flutter/material.dart';

/// Visual styling for the editor. Defaults derive from the host app's
/// [ThemeData] (the headless philosophy) and every field is overridable.
@immutable
class EditorStyle {
  const EditorStyle({
    required this.baseTextStyle,
    required this.headingStyles,
    required this.codeTextStyle,
    required this.linkColor,
    required this.selectionColor,
    required this.caretColor,
    this.padding = const EdgeInsets.all(16),
    this.blockSpacing = 12,
  });

  final TextStyle baseTextStyle;

  /// Heading text styles keyed by level (1–6).
  final Map<int, TextStyle> headingStyles;
  final TextStyle codeTextStyle;
  final Color linkColor;
  final Color selectionColor;
  final Color caretColor;
  final EdgeInsets padding;
  final double blockSpacing;

  /// The text style for a heading [level], falling back to the base style.
  TextStyle headingStyle(int level) =>
      headingStyles[level.clamp(1, 6)] ?? baseTextStyle;

  factory EditorStyle.fromTheme(ThemeData theme) {
    final base = (theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16))
        .copyWith(height: 1.5);
    final scheme = theme.colorScheme;
    TextStyle h(double size) =>
        base.copyWith(fontSize: size, fontWeight: FontWeight.w700, height: 1.3);
    return EditorStyle(
      baseTextStyle: base,
      headingStyles: {
        1: h(32),
        2: h(28),
        3: h(24),
        4: h(20),
        5: h(18),
        6: h(16),
      },
      codeTextStyle: base.copyWith(
        fontFamily: 'monospace',
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      linkColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.3),
      caretColor: scheme.primary,
    );
  }

  EditorStyle copyWith({
    TextStyle? baseTextStyle,
    Map<int, TextStyle>? headingStyles,
    TextStyle? codeTextStyle,
    Color? linkColor,
    Color? selectionColor,
    Color? caretColor,
    EdgeInsets? padding,
    double? blockSpacing,
  }) =>
      EditorStyle(
        baseTextStyle: baseTextStyle ?? this.baseTextStyle,
        headingStyles: headingStyles ?? this.headingStyles,
        codeTextStyle: codeTextStyle ?? this.codeTextStyle,
        linkColor: linkColor ?? this.linkColor,
        selectionColor: selectionColor ?? this.selectionColor,
        caretColor: caretColor ?? this.caretColor,
        padding: padding ?? this.padding,
        blockSpacing: blockSpacing ?? this.blockSpacing,
      );
}
