import 'package:meta/meta.dart';

/// Inline attributes attached to a run of text (e.g. `{'bold': true,
/// 'link': 'https://...'}`).
///
/// Kept as a plain map for ergonomics and trivial JSON round-tripping (the
/// appflowy pattern). The known inline-mark keys for the core are defined in
/// [InlineAttr]; plugins may add their own keys provided they register a
/// serializer (see the markdown pipeline).
typedef Attributes = Map<String, Object?>;

/// Canonical attribute keys for built-in inline marks.
@immutable
abstract final class InlineAttr {
  static const String bold = 'bold';
  static const String italic = 'italic';
  static const String strike = 'strike';
  static const String code = 'code';

  /// Link href (value is the URL string).
  static const String link = 'link';

  /// Inline math; value is the TeX source string.
  static const String math = 'math';

  /// Inline footnote reference; value is the footnote label string.
  static const String footnote = 'footnote';

  /// A hard line break (`  \n`); the run's text is a single newline.
  static const String hardBreak = 'hardBreak';
}

/// Deep-equality for two attribute maps (order-independent).
bool attributesEqual(Attributes? a, Attributes? b) {
  final aEmpty = a == null || a.isEmpty;
  final bEmpty = b == null || b.isEmpty;
  if (aEmpty && bEmpty) return true;
  if (aEmpty || bEmpty) return false;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Returns an immutable, normalized copy of [attrs] with null/false values
/// dropped so that "no mark" and "mark == false" compare equal.
Attributes normalizeAttributes(Attributes? attrs) {
  if (attrs == null || attrs.isEmpty) return const {};
  final out = <String, Object?>{};
  for (final entry in attrs.entries) {
    final v = entry.value;
    if (v == null) continue;
    if (v == false) continue;
    out[entry.key] = v;
  }
  return Map.unmodifiable(out);
}
