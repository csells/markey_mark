import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  String firstText(MarkdownEditorController c) =>
      (c.document.nodes.first as TextBlockNode).delta.toPlainText();

  DocumentSelection caret(String id, int o) =>
      DocumentSelection.collapsed(DocumentPosition.text(id, o));

  group('Construction + markdown access', () {
    test('empty controller has one empty paragraph', () {
      final c = MarkdownEditorController();
      expect(c.document.length, 1);
      expect(c.markdown, '');
      c.dispose();
    });

    test('seeds from markdown', () {
      final c = MarkdownEditorController(markdown: '# Title');
      expect(firstText(c), 'Title');
      expect(c.markdown, '# Title');
      c.dispose();
    });

    test('markdown setter replaces document (wysiwyg mode)', () {
      final c = MarkdownEditorController();
      c.markdown = 'Hello **world**';
      expect(firstText(c), 'Hello world');
      c.dispose();
    });

    test('custom input rules accepted', () {
      final c = MarkdownEditorController(inputRules: const []);
      expect(c.inputRules, isEmpty);
      c.dispose();
    });
  });

  group('Editing intents', () {
    late MarkdownEditorController c;
    late String id;
    setUp(() {
      c = MarkdownEditorController();
      id = c.document.nodes.first.id;
    });
    tearDown(() => c.dispose());

    test('insertText inserts and notifies', () {
      var notified = 0;
      c.addListener(() => notified++);
      c.setSelection(caret(id, 0));
      c.insertText('Hello');
      expect(firstText(c), 'Hello');
      expect(notified, greaterThan(0));
    });

    test('insertText applies the heading input rule', () {
      c.setSelection(caret(id, 0));
      c.insertText('#');
      c.setSelection(caret(id, 1));
      c.insertText(' ');
      final node = c.document.nodes.first as TextBlockNode;
      expect(node.type, BlockType.heading);
      expect(node.level, 1);
    });

    test('insertText applies the bold input rule', () {
      c.setSelection(caret(id, 0));
      c.insertText('**hi*');
      c.setSelection(caret(id, 5));
      c.insertText('*');
      final node = c.document.nodes.first as TextBlockNode;
      expect(node.delta.toPlainText(), 'hi');
      expect(node.delta.runs.single.attributes, {'bold': true});
    });

    test('deleteBackward', () {
      c.setSelection(caret(id, 0));
      c.insertText('Hello');
      c.deleteBackward();
      expect(firstText(c), 'Hell');
    });

    test('splitBlock', () {
      c.setSelection(caret(id, 0));
      c.insertText('AB');
      c.setSelection(caret(id, 1));
      c.splitBlock();
      expect(c.document.length, 2);
    });

    test('toggleMark over a range', () {
      c.setSelection(caret(id, 0));
      c.insertText('Hello');
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 0),
        extent: DocumentPosition.text(id, 5),
      ));
      c.toggleMark('bold');
      expect((c.document.nodes.first as TextBlockNode).delta.isFormatted(0, 5, 'bold'),
          isTrue);
    });

    test('setBlockType', () {
      c.setSelection(caret(id, 0));
      c.setBlockType(BlockType.heading, level: 3);
      expect((c.document.nodes.first as TextBlockNode).level, 3);
    });

    test('backspace immediately after an input rule reverts the transform', () {
      c.setSelection(caret(id, 0));
      c.insertText('# ');
      expect((c.document.nodes.first as TextBlockNode).type, BlockType.heading);
      c.deleteBackward();
      final n = c.document.nodes.first as TextBlockNode;
      expect(n.type, BlockType.paragraph);
      expect(n.delta.toPlainText(), '# ');
    });

    test('backspace after a normal edit deletes a character (no revert)', () {
      c.setSelection(caret(id, 0));
      c.insertText('ab');
      c.deleteBackward();
      expect(firstText(c), 'a');
    });

    test('caret movement disarms the rule-revert', () {
      c.setSelection(caret(id, 0));
      c.insertText('# '); // heading
      c.moveCaretLeft();
      c.deleteBackward();
      // Not reverted: still a heading (the move disarmed the revert).
      expect((c.document.nodes.first as TextBlockNode).type, BlockType.heading);
    });

    test('undo/redo', () {
      c.setSelection(caret(id, 0));
      c.insertText('X');
      expect(c.canUndo, isTrue);
      c.undo();
      expect(firstText(c), '');
      expect(c.canRedo, isTrue);
      c.redo();
      expect(firstText(c), 'X');
    });
  });

  group('Caret movement', () {
    late MarkdownEditorController c;
    late String id;
    setUp(() {
      c = MarkdownEditorController(markdown: 'Hello');
      id = c.document.nodes.first.id;
    });
    tearDown(() => c.dispose());

    test('left/right by character', () {
      c.setSelection(caret(id, 2));
      c.moveCaretRight();
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 3);
      c.moveCaretLeft();
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 2);
    });

    test('collapses a range to the correct edge', () {
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 1),
        extent: DocumentPosition.text(id, 4),
      ));
      c.moveCaretLeft();
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 1);
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 1),
        extent: DocumentPosition.text(id, 4),
      ));
      c.moveCaretRight();
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 4);
    });

    test('crosses block boundaries', () {
      final c2 = MarkdownEditorController(markdown: 'AB\n\nCD');
      final a = c2.document.nodes[0].id;
      final b = c2.document.nodes[1].id;
      c2.setSelection(caret(a, 2));
      c2.moveCaretRight();
      expect(c2.selection!.extent.nodeId, b);
      expect((c2.selection!.extent.nodePosition as TextNodePosition).offset, 0);
      c2.moveCaretLeft();
      expect(c2.selection!.extent.nodeId, a);
      expect((c2.selection!.extent.nodePosition as TextNodePosition).offset, 2);
      c2.dispose();
    });

    test('no-op without selection', () {
      c.setSelection(null);
      c.moveCaretLeft();
      c.moveCaretRight();
      expect(c.selection, isNull);
    });

    test('moves right over a multi-code-unit grapheme', () {
      final c2 = MarkdownEditorController(markdown: 'a😀b');
      final id2 = c2.document.nodes.first.id;
      c2.setSelection(caret(id2, 1)); // before the emoji
      c2.moveCaretRight();
      // Emoji is 2 UTF-16 code units; caret should land after it (offset 3).
      expect((c2.selection!.extent.nodePosition as TextNodePosition).offset, 3);
      c2.moveCaretLeft();
      expect((c2.selection!.extent.nodePosition as TextNodePosition).offset, 1);
      c2.dispose();
    });
  });

  group('Mode switching (single source of truth)', () {
    test('toggle wysiwyg <-> source preserves content', () {
      final c = MarkdownEditorController(markdown: '# Title');
      expect(c.mode, EditorMode.wysiwyg);
      c.toggleMode();
      expect(c.mode, EditorMode.source);
      expect(c.markdown, '# Title');
      c.dispose();
    });

    test('editing in source mode then toggling back re-parses', () {
      final c = MarkdownEditorController(markdown: 'plain');
      c.setMode(EditorMode.source);
      c.updateSourceText('## Updated');
      c.setMode(EditorMode.wysiwyg);
      final node = c.document.nodes.first as TextBlockNode;
      expect(node.type, BlockType.heading);
      expect(node.level, 2);
      expect(node.delta.toPlainText(), 'Updated');
      c.dispose();
    });

    test('markdown setter in source mode updates source text', () {
      final c = MarkdownEditorController();
      c.setMode(EditorMode.source);
      c.markdown = '# X';
      expect(c.markdown, '# X');
      c.dispose();
    });

    test('setMode is a no-op for the current mode', () {
      final c = MarkdownEditorController();
      c.setMode(EditorMode.wysiwyg);
      expect(c.mode, EditorMode.wysiwyg);
      c.dispose();
    });
  });
}
