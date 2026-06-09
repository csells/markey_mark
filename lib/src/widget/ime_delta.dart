import 'package:flutter/services.dart';

import '../model/document.dart';
import '../model/document_text.dart';
import '../model/node.dart';
import '../model/selection.dart';

/// The IME's **window**: a [DocumentText] over only the editable block(s) the
/// [selection] touches, plus one editable neighbour on each side — so the OS
/// never sees the whole document and a keystroke stays O(selection span + 2),
/// while backspace-at-start still merges with the previous block and Enter
/// splits flow into the next. Returns null when there's no editable block.
///
/// Pure (no widget state), so the windowing edge cases are unit-testable.
DocumentText? imeWindow(Document doc, DocumentSelection? selection) {
  bool editable(Node n) => n is TextBlockNode || n is CodeBlockNode;
  int lo;
  int hi;
  if (selection == null) {
    lo = hi = 0;
  } else {
    final iBase = doc.indexOfId(selection.base.nodeId);
    final iExt = doc.indexOfId(selection.extent.nodeId);
    if (iBase < 0 || iExt < 0) {
      lo = hi = 0;
    } else {
      lo = iBase < iExt ? iBase : iExt;
      hi = iBase < iExt ? iExt : iBase;
    }
  }
  final from = (lo - 1).clamp(0, doc.length - 1);
  final to = (hi + 1).clamp(0, doc.length - 1);
  final window = <Node>[
    for (var i = from; i <= to; i++)
      if (editable(doc.nodeAt(i))) doc.nodeAt(i),
  ];
  if (window.isEmpty) {
    // Fall back to the first editable block so an empty doc still types.
    final first = doc.length > 0 ? doc.nodeAt(0) : null;
    if (first != null && editable(first)) window.add(first);
  }
  if (window.isEmpty) return null;
  return DocumentText.of(Document(window));
}

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
