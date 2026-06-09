import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  String text(MarkdownEditorController c, int i) =>
      (c.document.nodes[i] as TextBlockNode).delta.toPlainText();

  group('findInDocument', () {
    test('finds all matches across blocks (case-insensitive default)', () {
      final c = MarkdownEditorController(markdown: 'Hello hello\n\nHELLO');
      final m = findInDocument(c.document, 'hello');
      expect(m.length, 3);
      c.dispose();
    });

    test('respects case sensitivity', () {
      final c = MarkdownEditorController(markdown: 'Hello hello HELLO');
      expect(findInDocument(c.document, 'hello', caseSensitive: true).length, 1);
      c.dispose();
    });

    test('empty query yields no matches', () {
      final c = MarkdownEditorController(markdown: 'abc');
      expect(findInDocument(c.document, ''), isEmpty);
      c.dispose();
    });

    test('reports correct nodeId/start/end', () {
      final c = MarkdownEditorController(markdown: 'a cat sat');
      final m = findInDocument(c.document, 'cat').single;
      expect(m.nodeId, c.document.nodes.first.id);
      expect(m.start, 2);
      expect(m.end, 5);
      c.dispose();
    });
  });

  group('MatchLocation + non-text', () {
    test('value semantics', () {
      const a = MatchLocation(nodeId: 'n', start: 1, end: 3);
      expect(a, const MatchLocation(nodeId: 'n', start: 1, end: 3));
      expect(a == const MatchLocation(nodeId: 'n', start: 1, end: 4), isFalse);
      expect(a.hashCode, const MatchLocation(nodeId: 'n', start: 1, end: 3).hashCode);
      expect(a.toString(), contains('MatchLocation'));
    });

    test('skips non-text blocks (e.g. tables)', () {
      final c = MarkdownEditorController(
          markdown: '| cat | dog |\n| --- | --- |\n| 1 | 2 |');
      expect(findInDocument(c.document, 'cat'), isEmpty);
      c.dispose();
    });

    test('replaceMatch on a non-text node is a no-op', () {
      final c = MarkdownEditorController(markdown: '---');
      c.replaceMatch(
          const MatchLocation(nodeId: 'nope', start: 0, end: 1), 'x');
      expect(c.markdown, '---');
      c.dispose();
    });
  });

  group('controller find/replace', () {
    test('selectMatch moves the selection to the match', () {
      final c = MarkdownEditorController(markdown: 'a cat sat');
      final m = c.findMatches('cat').single;
      c.selectMatch(m);
      expect(c.selection!.isCollapsed, isFalse);
      expect((c.selection!.base.nodePosition as TextNodePosition).offset, 2);
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 5);
      c.dispose();
    });

    test('replaceAll replaces every occurrence', () {
      final c = MarkdownEditorController(markdown: 'oo and oo\n\noo');
      c.replaceAll('oo', 'X');
      expect(text(c, 0), 'X and X');
      expect(text(c, 1), 'X');
      c.dispose();
    });

    test('replaceAll is a single undo unit', () {
      final c = MarkdownEditorController(markdown: 'oo oo');
      c.replaceAll('oo', 'X');
      expect(text(c, 0), 'X X');
      c.undo();
      expect(text(c, 0), 'oo oo');
      c.dispose();
    });

    test('replaceMatch replaces one occurrence and preserves the rest', () {
      final c = MarkdownEditorController(markdown: 'oo oo');
      final first = c.findMatches('oo').first;
      c.replaceMatch(first, 'X');
      expect(text(c, 0), 'X oo');
      c.dispose();
    });

    test('replaceAll no-ops on empty query', () {
      final c = MarkdownEditorController(markdown: 'abc');
      c.replaceAll('', 'X');
      expect(text(c, 0), 'abc');
      c.dispose();
    });
  });
}
