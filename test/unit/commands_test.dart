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

  DocumentSelection caret(String id, int o) =>
      DocumentSelection.collapsed(DocumentPosition.text(id, o));

  DocumentSelection range(String id, int a, int b) => DocumentSelection(
        base: DocumentPosition.text(id, a),
        extent: DocumentPosition.text(id, b),
      );

  String textOf(Document d, String id) =>
      (d.nodeById(id) as TextBlockNode).delta.toPlainText();

  group('insertText', () {
    test('inserts at caret', () {
      final doc = Document([p('a', 'Helo')]);
      final txn = EditCommands.insertText(doc, caret('a', 3), 'l')!;
      final after = txn.apply(doc);
      expect(textOf(after, 'a'), 'Hello');
      expect(txn.selectionAfter, caret('a', 4));
      expect(txn.tag, 'typing');
    });

    test('replaces selected range', () {
      final doc = Document([p('a', 'Hello')]);
      final txn = EditCommands.insertText(doc, range('a', 0, 5), 'Bye')!;
      expect(textOf(txn.apply(doc), 'a'), 'Bye');
    });

    test('inherits attributes from preceding character', () {
      final doc = Document([
        TextBlockNode.paragraph(id: 'a', delta: Delta.text('Hi', {'bold': true})),
      ]);
      final txn = EditCommands.insertText(doc, caret('a', 2), '!')!;
      final node = txn.apply(doc).nodeById('a') as TextBlockNode;
      expect(node.delta.runs.single.attributes, {'bold': true});
    });

    test('returns null for empty text or no selection', () {
      final doc = Document([p('a', 'x')]);
      expect(EditCommands.insertText(doc, caret('a', 0), ''), isNull);
      expect(EditCommands.insertText(doc, null, 'x'), isNull);
    });

    test('returns null for multi-block selection', () {
      final doc = Document([p('a', 'x'), p('b', 'y')]);
      final sel = DocumentSelection(
        base: DocumentPosition.text('a', 0),
        extent: DocumentPosition.text('b', 1),
      );
      expect(EditCommands.insertText(doc, sel, 'z'), isNull);
    });
  });

  group('deleteBackward', () {
    test('deletes one character before caret', () {
      final doc = Document([p('a', 'Hello')]);
      final txn = EditCommands.deleteBackward(doc, caret('a', 5))!;
      expect(textOf(txn.apply(doc), 'a'), 'Hell');
      expect(txn.selectionAfter, caret('a', 4));
    });

    test('deletes selected range', () {
      final doc = Document([p('a', 'Hello')]);
      final txn = EditCommands.deleteBackward(doc, range('a', 1, 4))!;
      expect(textOf(txn.apply(doc), 'a'), 'Ho');
      expect(txn.selectionAfter, caret('a', 1));
    });

    test('is grapheme-aware (emoji deleted as one unit)', () {
      final doc = Document([p('a', 'a👨‍👩‍👧b')]);
      final family = '👨‍👩‍👧';
      final txn = EditCommands.deleteBackward(doc, caret('a', 1 + family.length))!;
      expect(textOf(txn.apply(doc), 'a'), 'ab');
    });

    test('merges with previous block at offset 0', () {
      final doc = Document([p('a', 'Hello'), p('b', 'World')]);
      final txn = EditCommands.deleteBackward(doc, caret('b', 0))!;
      final after = txn.apply(doc);
      expect(after.length, 1);
      expect(textOf(after, 'a'), 'HelloWorld');
      expect(txn.selectionAfter, caret('a', 5));
    });

    test('no-op at very start of document', () {
      final doc = Document([p('a', 'Hello')]);
      expect(EditCommands.deleteBackward(doc, caret('a', 0)), isNull);
    });
  });

  group('splitBlock', () {
    test('splits at caret; trailing becomes a paragraph', () {
      final doc = Document([
        TextBlockNode.heading(id: 'a', level: 1, delta: Delta.text('HelloWorld')),
      ]);
      final txn = EditCommands.splitBlock(doc, caret('a', 5))!;
      final after = txn.apply(doc);
      expect(after.length, 2);
      expect((after.nodes[0] as TextBlockNode).type, BlockType.heading);
      expect(textOf(after, 'a'), 'Hello');
      expect((after.nodes[1] as TextBlockNode).type, BlockType.paragraph);
      expect((after.nodes[1] as TextBlockNode).delta.toPlainText(), 'World');
      expect(txn.selectionAfter!.extent.nodeId, after.nodes[1].id);
    });

    test('splits removing a selected range', () {
      final doc = Document([p('a', 'abcdef')]);
      final txn = EditCommands.splitBlock(doc, range('a', 2, 4))!;
      final after = txn.apply(doc);
      expect(textOf(after, 'a'), 'ab');
      expect((after.nodes[1] as TextBlockNode).delta.toPlainText(), 'ef');
    });
  });

  group('toggleMark', () {
    test('adds a mark over a range', () {
      final doc = Document([p('a', 'Hello')]);
      final txn = EditCommands.toggleMark(doc, range('a', 0, 5), 'bold')!;
      final node = txn.apply(doc).nodeById('a') as TextBlockNode;
      expect(node.delta.isFormatted(0, 5, 'bold'), isTrue);
    });

    test('removes when already formatted', () {
      final doc = Document([
        TextBlockNode.paragraph(id: 'a', delta: Delta.text('Hi', {'bold': true})),
      ]);
      final txn = EditCommands.toggleMark(doc, range('a', 0, 2), 'bold')!;
      final node = txn.apply(doc).nodeById('a') as TextBlockNode;
      expect(node.delta.runs.single.attributes, isEmpty);
    });

    test('null on collapsed selection', () {
      final doc = Document([p('a', 'Hi')]);
      expect(EditCommands.toggleMark(doc, caret('a', 1), 'bold'), isNull);
    });
  });

  group('setBlockType', () {
    test('paragraph to heading', () {
      final doc = Document([p('a', 'Title')]);
      final txn = EditCommands.setBlockType(doc, caret('a', 0),
          BlockType.heading, level: 2)!;
      final node = txn.apply(doc).nodeById('a') as TextBlockNode;
      expect(node.type, BlockType.heading);
      expect(node.level, 2);
    });

    test('null when already that type/level', () {
      final doc = Document([
        TextBlockNode.heading(id: 'a', level: 2, delta: Delta.text('T')),
      ]);
      expect(
        EditCommands.setBlockType(doc, caret('a', 0), BlockType.heading, level: 2),
        isNull,
      );
    });
  });
}
