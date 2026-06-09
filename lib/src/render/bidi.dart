import 'package:flutter/painting.dart' show TextDirection;

/// Resolves the **base direction** of [text] from its first strong directional
/// character (the UAX #9 paragraph-direction rule, P2/P3): the first character
/// with a strong Left-to-Right or Right-to-Left bidi class decides the
/// paragraph direction; leading neutrals (spaces, digits, punctuation, emoji)
/// are skipped. Defaults to [TextDirection.ltr] when there is no strong
/// character.
///
/// This is enough for per-paragraph base direction (so Arabic/Hebrew render and
/// align correctly); Flutter's `TextPainter` then handles intra-line bidi
/// reordering, caret geometry, and selection rects for free once it knows the
/// base direction.
TextDirection resolveBaseDirection(String text) {
  for (final rune in text.runes) {
    if (_isStrongRtl(rune)) return TextDirection.rtl;
    if (_isStrongLtr(rune)) return TextDirection.ltr;
  }
  return TextDirection.ltr;
}

/// The strong bidi direction of a single [rune], or null for neutrals (spaces,
/// digits, punctuation, symbols). Lets the caret move *visually* per-run in
/// mixed-direction text rather than per-paragraph.
TextDirection? strongDirectionOf(int rune) {
  if (_isStrongRtl(rune)) return TextDirection.rtl;
  if (_isStrongLtr(rune)) return TextDirection.ltr;
  return null;
}

/// True if [rune] has a strong RTL bidi class (Hebrew, Arabic, Syriac, Thaana,
/// NKo, and the Arabic presentation forms).
bool _isStrongRtl(int rune) =>
    (rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
    (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
    (rune >= 0x0700 && rune <= 0x074F) || // Syriac
    (rune >= 0x0750 && rune <= 0x077F) || // Arabic Supplement
    (rune >= 0x0780 && rune <= 0x07BF) || // Thaana
    (rune >= 0x07C0 && rune <= 0x07FF) || // NKo
    (rune >= 0x08A0 && rune <= 0x08FF) || // Arabic Extended-A
    (rune >= 0xFB1D && rune <= 0xFB4F) || // Hebrew presentation forms
    (rune >= 0xFB50 && rune <= 0xFDFF) || // Arabic presentation forms-A
    (rune >= 0xFE70 && rune <= 0xFEFF); // Arabic presentation forms-B

/// True if [rune] has a strong LTR bidi class (Latin/Greek/Cyrillic and most
/// other scripts — approximated as "a letter that isn't strong-RTL").
bool _isStrongLtr(int rune) {
  if (_isStrongRtl(rune)) return false;
  // ASCII letters (the common fast path).
  if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A)) {
    return true;
  }
  // Other Basic-Multilingual-Plane letters above Latin-1, excluding the neutral
  // punctuation/symbol/emoji ranges, are treated as strong LTR. CJK, Cyrillic,
  // Greek, Devanagari, etc. all fall here.
  if (rune >= 0x00C0 && rune <= 0x024F) return true; // Latin extended
  if (rune >= 0x0370 && rune <= 0x03FF) return true; // Greek
  if (rune >= 0x0400 && rune <= 0x04FF) return true; // Cyrillic
  if (rune >= 0x0900 && rune <= 0x097F) return true; // Devanagari
  if (rune >= 0x3040 && rune <= 0x30FF) return true; // Hiragana/Katakana
  if (rune >= 0x4E00 && rune <= 0x9FFF) return true; // CJK unified
  if (rune >= 0xAC00 && rune <= 0xD7AF) return true; // Hangul
  return false;
}
