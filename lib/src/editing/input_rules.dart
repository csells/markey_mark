import '../model/document.dart';
import '../model/node.dart';
import '../model/position.dart';
import '../model/selection.dart';
import 'operations.dart';
import 'transaction.dart';

/// A live Markdown "magic" rule: inspects the text immediately before the caret
/// and, on a match, returns a transform [EditTransaction] (tagged
/// `'input-rule'` so it's a single undo unit, distinct from typing).
///
/// Rules are evaluated after each text insertion. Because each rule's pattern
/// ends at the caret and the transform removes the trigger characters, a rule
/// fires exactly once.
abstract class InputRule {
  const InputRule();

  /// Returns a transform transaction, or null if this rule doesn't apply.
  EditTransaction? match(Document doc, DocumentSelection selection);
}

/// Shared helpers for the built-in rules.
abstract final class _RuleContext {
  /// Returns (node, index, offset, textBeforeCaret) for a collapsed selection
  /// inside a text block, or null.
  static (TextBlockNode, int, int, String)? caretInText(
    Document doc,
    DocumentSelection selection,
  ) {
    if (!selection.isCollapsed) return null;
    final pos = selection.extent;
    final node = doc.nodeById(pos.nodeId);
    if (node is! TextBlockNode) return null;
    final np = pos.nodePosition;
    if (np is! TextNodePosition) return null;
    final index = doc.indexOfId(node.id);
    final plain = node.delta.toPlainText();
    if (np.offset > plain.length) return null;
    return (node, index, np.offset, plain.substring(0, np.offset));
  }
}

/// `#`..`######` + space at the start of a paragraph → heading.
class HeadingInputRule extends InputRule {
  const HeadingInputRule();
  static final RegExp _pattern = RegExp(r'^(#{1,6}) $');

  @override
  EditTransaction? match(Document doc, DocumentSelection selection) {
    final ctx = _RuleContext.caretInText(doc, selection);
    if (ctx == null) return null;
    final (node, index, offset, before) = ctx;
    if (node.type != BlockType.paragraph) return null;
    final m = _pattern.firstMatch(before);
    if (m == null) return null;
    final level = m.group(1)!.length;
    final prefixLen = level + 1; // hashes + space
    final newDelta = node.delta.delete(0, prefixLen);
    final newNode =
        TextBlockNode.heading(id: node.id, level: level, delta: newDelta);
    return EditTransaction(
      operations: [ReplaceNodeOp(index, node, newNode)],
      selectionBefore: selection,
      selectionAfter: DocumentSelection.collapsed(
        DocumentPosition.text(node.id, offset - prefixLen),
      ),
      tag: 'input-rule',
    );
  }
}

/// A symmetric inline wrap rule: `<delim>text<delim>` → text with [attr].
/// Triggered when the closing delimiter is typed.
class WrapInputRule extends InputRule {
  const WrapInputRule({required this.pattern, required this.attr});

  /// Must capture the inner content in group 1 and end at the caret (`$`).
  final RegExp pattern;
  final String attr;

  @override
  EditTransaction? match(Document doc, DocumentSelection selection) {
    final ctx = _RuleContext.caretInText(doc, selection);
    if (ctx == null) return null;
    final (node, index, offset, before) = ctx;
    final m = pattern.firstMatch(before);
    if (m == null) return null;
    final content = m.group(1)!;
    if (content.isEmpty) return null;
    final matchStart = offset - m.group(0)!.length;
    final newDelta = node.delta
        .delete(matchStart, offset)
        .insert(matchStart, content, {attr: true});
    final newNode = node.copyWithDelta(newDelta);
    return EditTransaction(
      operations: [ReplaceNodeOp(index, node, newNode)],
      selectionBefore: selection,
      selectionAfter: DocumentSelection.collapsed(
        DocumentPosition.text(node.id, matchStart + content.length),
      ),
      tag: 'input-rule',
    );
  }
}

/// The default ordered rule set for the vertical slice.
///
/// Bold uses `**…**`, italic `_…_`, inline code `` `…` ``, strike `~~…~~`. We
/// use `_` for italic (not `*`) to avoid colliding with `**bold**`.
final List<InputRule> defaultInputRules = [
  const HeadingInputRule(),
  WrapInputRule(pattern: RegExp(r'\*\*([^*]+)\*\*$'), attr: 'bold'),
  WrapInputRule(pattern: RegExp(r'~~([^~]+)~~$'), attr: 'strike'),
  WrapInputRule(pattern: RegExp(r'(?<![\w_])_([^_]+)_$'), attr: 'italic'),
  WrapInputRule(pattern: RegExp(r'`([^`]+)`$'), attr: 'code'),
];

/// Runs [rules] in order, returning the first matching transform or null.
EditTransaction? applyInputRules(
  Document doc,
  DocumentSelection? selection, {
  List<InputRule> rules = const [],
}) {
  if (selection == null) return null;
  for (final rule in rules) {
    final txn = rule.match(doc, selection);
    if (txn != null) return txn;
  }
  return null;
}
