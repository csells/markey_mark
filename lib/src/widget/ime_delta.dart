import 'package:flutter/services.dart';

/// Translates a single [TextEditingDelta] into a minimal block-local edit
/// `(start, deletedCount, insertedText)`, or null for a selection/composing-only
/// update.
///
/// This is the precise replacement for diffing two `TextEditingValue` strings:
/// the platform reports exactly what changed (including IME composition and
/// autocorrect replacements), so there is no ambiguity to guess at.
(int start, int deleted, String inserted)? editFromDelta(TextEditingDelta d) {
  if (d is TextEditingDeltaInsertion) {
    return (d.insertionOffset, 0, d.textInserted);
  }
  if (d is TextEditingDeltaDeletion) {
    return (d.deletedRange.start, d.deletedRange.end - d.deletedRange.start, '');
  }
  if (d is TextEditingDeltaReplacement) {
    return (
      d.replacedRange.start,
      d.replacedRange.end - d.replacedRange.start,
      d.replacementText,
    );
  }
  return null; // TextEditingDeltaNonTextUpdate
}
