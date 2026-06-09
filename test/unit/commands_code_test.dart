import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/editing/commands.dart';
import 'package:markey_mark/src/model/document.dart';
import 'package:markey_mark/src/model/node.dart';
import 'package:markey_mark/src/model/position.dart';
import 'package:markey_mark/src/model/selection.dart';

/// Step 5: code blocks are editable regions of the one editor — edits route
/// through the same command pipeline as text blocks (operating on `code`).
void main() {
  CodeBlockNode code(String id, String src, [String? lang]) =>
      CodeBlockNode(id: id, code: src, language: lang);

  DocumentSelection caret(String id, int o) =>
      DocumentSelection.collapsed(DocumentPosition.text(id, o));

  DocumentSelection range(String id, int a, int b) => DocumentSelection(
        base: DocumentPosition.text(id, a),
        extent: DocumentPosition.text(id, b),
      );

  String codeOf(Document d, String id) => (d.nodeById(id) as CodeBlockNode).code;

  group('insertText into a code block', () {
    test('inserts into the code at the caret', () {
      final doc = Document([code('c', 'ab')]);
      final txn = EditCommands.insertText(doc, caret('c', 1), 'X')!;
      final after = txn.apply(doc);
      expect(codeOf(after, 'c'), 'aXb');
      expect(txn.selectionAfter, caret('c', 2));
    });

    test('replaces a selected range', () {
      final doc = Document([code('c', 'hello')]);
      final txn = EditCommands.insertText(doc, range('c', 1, 4), 'Y')!;
      expect(codeOf(txn.apply(doc), 'c'), 'hYo');
    });
  });

  group('deleteBackward in a code block', () {
    test('deletes the char before the caret', () {
      final doc = Document([code('c', 'abc')]);
      final txn = EditCommands.deleteBackward(doc, caret('c', 2))!;
      expect(codeOf(txn.apply(doc), 'c'), 'ac');
      expect(txn.selectionAfter, caret('c', 1));
    });

    test('deletes a selected range', () {
      final doc = Document([code('c', 'abcd')]);
      final txn = EditCommands.deleteBackward(doc, range('c', 1, 3))!;
      expect(codeOf(txn.apply(doc), 'c'), 'ad');
    });
  });

  group('newline inside a code block', () {
    test('splitBlock inserts a literal newline into the code (stays one block)',
        () {
      final doc = Document([code('c', 'ab')]);
      final txn = EditCommands.splitBlock(doc, caret('c', 1))!;
      final after = txn.apply(doc);
      expect(after.length, 1);
      expect(codeOf(after, 'c'), 'a\nb');
      expect(txn.selectionAfter, caret('c', 2));
    });
  });
}
