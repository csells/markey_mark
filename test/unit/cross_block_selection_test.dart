import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/editing/commands.dart';
import 'package:markey_mark/src/model/delta.dart';
import 'package:markey_mark/src/model/document.dart';
import 'package:markey_mark/src/model/node.dart';
import 'package:markey_mark/src/model/position.dart';
import 'package:markey_mark/src/model/selection.dart';

void main() {
  TextBlockNode p(String id, String text) =>
      TextBlockNode.paragraph(id: id, delta: Delta.text(text));

  DocumentSelection cross(String aId, int a, String bId, int b) =>
      DocumentSelection(
        base: DocumentPosition.text(aId, a),
        extent: DocumentPosition.text(bId, b),
      );

  DocumentSelection caret(String id, int o) =>
      DocumentSelection.collapsed(DocumentPosition.text(id, o));

  String textOf(Document d, String id) =>
      (d.nodeById(d.indexOfId(id) >= 0 ? id : id) as TextBlockNode)
          .delta
          .toPlainText();

  group('deleteSelection (cross-block)', () {
    test('merges the partial first and last blocks, drops the middle', () {
      final doc = Document([p('a', 'Hello'), p('b', 'cruel'), p('c', 'World')]);
      // From "Hel|lo" to "Wor|ld"
      final txn = EditCommands.deleteSelection(doc, cross('a', 3, 'c', 3))!;
      final after = txn.apply(doc);
      expect(after.length, 1);
      expect(textOf(after, 'a'), 'Helld');
      expect(after.nodeById('b'), isNull);
      expect(after.nodeById('c'), isNull);
      expect(txn.selectionAfter, caret('a', 3));
    });

    test('works regardless of selection direction (extent before base)', () {
      final doc = Document([p('a', 'Hello'), p('b', 'World')]);
      final txn = EditCommands.deleteSelection(doc, cross('b', 2, 'a', 2))!;
      final after = txn.apply(doc);
      expect(textOf(after, 'a'), 'Herld');
    });

    test('the surviving block keeps the first block type', () {
      final doc = Document([
        TextBlockNode.heading(level: 2, delta: Delta.text('Title'), id: 'a'),
        p('b', 'body'),
      ]);
      final txn = EditCommands.deleteSelection(doc, cross('a', 5, 'b', 2))!;
      final after = txn.apply(doc);
      final node = after.nodeById('a') as TextBlockNode;
      expect(node.type, BlockType.heading);
      expect(node.level, 2);
      expect(node.delta.toPlainText(), 'Titledy');
    });

    test('is invertible (undo restores all three blocks)', () {
      final doc = Document([p('a', 'Hello'), p('b', 'cruel'), p('c', 'World')]);
      final txn = EditCommands.deleteSelection(doc, cross('a', 3, 'c', 3))!;
      final after = txn.apply(doc);
      final restored = txn.inverse().apply(after);
      expect(restored, doc);
    });

    test('returns null for a single-block (collapsed or same-node) selection',
        () {
      final doc = Document([p('a', 'Hello')]);
      expect(EditCommands.deleteSelection(doc, caret('a', 2)), isNull);
      expect(EditCommands.deleteSelection(doc, null), isNull);
    });
  });

  group('insertText (cross-block)', () {
    test('replaces a cross-block selection with the typed text', () {
      final doc = Document([p('a', 'Hello'), p('b', 'World')]);
      final txn = EditCommands.insertText(doc, cross('a', 3, 'b', 2), 'X')!;
      final after = txn.apply(doc);
      expect(after.length, 1);
      expect(textOf(after, 'a'), 'HelXrld');
      expect(txn.selectionAfter, caret('a', 4));
    });
  });

  group('deleteBackward (cross-block)', () {
    test('deletes a cross-block selection like deleteSelection', () {
      final doc = Document([p('a', 'Hello'), p('b', 'World')]);
      final txn = EditCommands.deleteBackward(doc, cross('a', 3, 'b', 2))!;
      final after = txn.apply(doc);
      expect(after.length, 1);
      expect(textOf(after, 'a'), 'Helrld');
    });
  });

  group('toggleMark (cross-block)', () {
    test('applies the mark across every spanned block portion', () {
      final doc = Document([p('a', 'Hello'), p('b', 'World')]);
      final txn = EditCommands.toggleMark(doc, cross('a', 2, 'b', 3), 'bold')!;
      final after = txn.apply(doc);
      final na = after.nodeById('a') as TextBlockNode;
      final nb = after.nodeById('b') as TextBlockNode;
      expect(na.delta.isFormatted(2, 5, 'bold'), isTrue);
      expect(nb.delta.isFormatted(0, 3, 'bold'), isTrue);
    });
  });
}
