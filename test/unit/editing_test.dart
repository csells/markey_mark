import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/editing/editor.dart';
import 'package:markey_mark/src/editing/operations.dart';
import 'package:markey_mark/src/editing/transaction.dart';
import 'package:markey_mark/src/model/delta.dart';
import 'package:markey_mark/src/model/document.dart';
import 'package:markey_mark/src/model/node.dart';
import 'package:markey_mark/src/model/position.dart';
import 'package:markey_mark/src/model/selection.dart';

void main() {
  TextBlockNode p(String id, String text) =>
      TextBlockNode.paragraph(id: id, delta: Delta.text(text));

  group('Operations apply + inverse', () {
    test('InsertNodeOp / inverse', () {
      final doc = Document([p('a', 'A')]);
      final op = InsertNodeOp(1, p('b', 'B'));
      final after = op.apply(doc);
      expect(after.length, 2);
      final back = op.inverse().apply(after);
      expect(back, doc);
      expect(op.toString(), contains('InsertNodeOp'));
    });

    test('DeleteNodeOp / inverse', () {
      final b = p('b', 'B');
      final doc = Document([p('a', 'A'), b]);
      final op = DeleteNodeOp(1, b);
      final after = op.apply(doc);
      expect(after.length, 1);
      expect(op.inverse().apply(after), doc);
      expect(op.toString(), contains('DeleteNodeOp'));
    });

    test('ReplaceNodeOp / inverse', () {
      final before = p('a', 'A');
      final after = p('a', 'AA');
      final doc = Document([before]);
      final op = ReplaceNodeOp(0, before, after);
      final applied = op.apply(doc);
      expect((applied.nodes.first as TextBlockNode).delta.toPlainText(), 'AA');
      expect(op.inverse().apply(applied), doc);
      expect(op.toString(), contains('ReplaceNodeOp'));
    });
  });

  group('EditTransaction', () {
    test('applies ops in order and inverts (reverse + swap)', () {
      final doc = Document([p('a', 'A')]);
      final sb = DocumentSelection.collapsed(DocumentPosition.text('a', 1));
      final sa = DocumentSelection.collapsed(DocumentPosition.text('b', 0));
      final txn = EditTransaction(
        operations: [
          ReplaceNodeOp(0, p('a', 'A'), p('a', 'AB')),
          InsertNodeOp(1, p('b', 'C')),
        ],
        selectionBefore: sb,
        selectionAfter: sa,
      );
      final applied = txn.apply(doc);
      expect(applied.length, 2);
      final inv = txn.inverse();
      expect(inv.apply(applied), doc);
      expect(inv.selectionAfter, sb);
      expect(inv.selectionBefore, sa);
      expect(txn.isEmpty, isFalse);
      expect(txn.toString(), contains('EditTransaction'));
    });
  });

  group('Editor', () {
    late Editor editor;
    setUp(() {
      editor = Editor(document: Document([p('a', 'A')]));
    });

    test('initial state', () {
      expect(editor.document.length, 1);
      expect(editor.canUndo, isFalse);
      expect(editor.canRedo, isFalse);
      expect(editor.selection, isNull);
    });

    test('apply records undo and updates selection + notifies', () {
      var notified = 0;
      editor.addListener(() => notified++);
      final sa = DocumentSelection.collapsed(DocumentPosition.text('a', 2));
      editor.apply(EditTransaction(
        operations: [ReplaceNodeOp(0, p('a', 'A'), p('a', 'AB'))],
        selectionAfter: sa,
      ));
      expect((editor.document.nodes.first as TextBlockNode).delta.toPlainText(),
          'AB');
      expect(editor.canUndo, isTrue);
      expect(editor.selection, sa);
      expect(notified, greaterThan(0));
    });

    test('undo and redo restore document + selection', () {
      final before = p('a', 'A');
      editor.apply(EditTransaction(
        operations: [ReplaceNodeOp(0, before, p('a', 'AB'))],
        selectionBefore: DocumentSelection.collapsed(DocumentPosition.text('a', 1)),
        selectionAfter: DocumentSelection.collapsed(DocumentPosition.text('a', 2)),
      ));
      editor.undo();
      expect((editor.document.nodes.first as TextBlockNode).delta.toPlainText(),
          'A');
      expect(editor.canRedo, isTrue);
      expect(editor.selection,
          DocumentSelection.collapsed(DocumentPosition.text('a', 1)));
      editor.redo();
      expect((editor.document.nodes.first as TextBlockNode).delta.toPlainText(),
          'AB');
      expect(editor.selection,
          DocumentSelection.collapsed(DocumentPosition.text('a', 2)));
    });

    test('undo/redo are no-ops when stacks are empty', () {
      editor.undo();
      editor.redo();
      expect(editor.document.length, 1);
    });

    test('mergeable typing transactions coalesce into one undo unit', () {
      ReplaceNodeOp grow(String from, String to) =>
          ReplaceNodeOp(0, p('a', from), p('a', to));
      editor.apply(EditTransaction(operations: [grow('A', 'AB')], tag: 'typing'));
      editor.apply(EditTransaction(operations: [grow('AB', 'ABC')], tag: 'typing'));
      editor.undo();
      // Both coalesced → single undo returns to 'A'.
      expect((editor.document.nodes.first as TextBlockNode).delta.toPlainText(),
          'A');
    });

    test('non-mergeable tags stay separate', () {
      editor.apply(EditTransaction(
        operations: [ReplaceNodeOp(0, p('a', 'A'), p('a', 'AB'))],
        tag: 'typing',
      ));
      editor.apply(EditTransaction(
        operations: [ReplaceNodeOp(0, p('a', 'AB'), p('a', 'XB'))],
        tag: 'input-rule',
      ));
      editor.undo();
      expect((editor.document.nodes.first as TextBlockNode).delta.toPlainText(),
          'AB');
    });

    test('new edit clears redo stack', () {
      editor.apply(EditTransaction(
          operations: [ReplaceNodeOp(0, p('a', 'A'), p('a', 'AB'))]));
      editor.undo();
      expect(editor.canRedo, isTrue);
      editor.apply(EditTransaction(
          operations: [ReplaceNodeOp(0, p('a', 'A'), p('a', 'AC'))]));
      expect(editor.canRedo, isFalse);
    });

    test('setSelection notifies only on change', () {
      var notified = 0;
      editor.addListener(() => notified++);
      final s = DocumentSelection.collapsed(DocumentPosition.text('a', 0));
      editor.setSelection(s);
      editor.setSelection(s);
      expect(notified, 1);
    });

    test('setDocument clears history', () {
      editor.apply(EditTransaction(
          operations: [ReplaceNodeOp(0, p('a', 'A'), p('a', 'AB'))]));
      editor.setDocument(Document([p('z', 'Z')]));
      expect(editor.canUndo, isFalse);
      expect(editor.document.nodeById('z'), isNotNull);
    });

    test('empty transaction with no selection is ignored', () {
      var notified = 0;
      editor.addListener(() => notified++);
      editor.apply(const EditTransaction(operations: []));
      expect(notified, 0);
    });
  });
}
