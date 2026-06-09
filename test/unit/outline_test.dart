import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  group('outline', () {
    test('lists headings in document order with level and text', () {
      final c = MarkdownEditorController(
        markdown: '# Title\n\nintro\n\n## Section A\n\n### Detail\n\n## Section B',
      );
      final o = c.outline();
      expect(o.map((e) => e.text), ['Title', 'Section A', 'Detail', 'Section B']);
      expect(o.map((e) => e.level), [1, 2, 3, 2]);
      c.dispose();
    });

    test('entries carry the heading block id', () {
      final c = MarkdownEditorController(markdown: '# Only');
      final entry = c.outline().single;
      final headingId = c.document.nodes.first.id;
      expect(entry.nodeId, headingId);
      c.dispose();
    });

    test('uses plain text, dropping inline formatting markers', () {
      final c = MarkdownEditorController(markdown: '## A **bold** word');
      expect(c.outline().single.text, 'A bold word');
      c.dispose();
    });

    test('ignores non-heading blocks', () {
      final c = MarkdownEditorController(markdown: 'para\n\n- item\n\n> quote');
      expect(c.outline(), isEmpty);
      c.dispose();
    });

    test('is empty for an empty document', () {
      final c = MarkdownEditorController();
      expect(c.outline(), isEmpty);
      c.dispose();
    });
  });
}
