import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  group('tableOfContents', () {
    test('builds a nested Markdown list linking to heading slugs', () {
      final c = MarkdownEditorController(markdown: '# A\n\n## B\n\n## C');
      expect(c.tableOfContents(), '- [A](#a)\n  - [B](#b)\n  - [C](#c)');
      c.dispose();
    });

    test('indents relative to the shallowest heading level', () {
      final c = MarkdownEditorController(markdown: '## Top\n\n### Sub');
      expect(c.tableOfContents(), '- [Top](#top)\n  - [Sub](#sub)');
      c.dispose();
    });

    test('deduplicates repeated slugs like HTML export', () {
      final c = MarkdownEditorController(markdown: '# Intro\n\n# Intro');
      expect(c.tableOfContents(), '- [Intro](#intro)\n- [Intro](#intro-1)');
      c.dispose();
    });

    test('is empty when there are no headings', () {
      final c = MarkdownEditorController(markdown: 'just a paragraph');
      expect(c.tableOfContents(), '');
      c.dispose();
    });
  });

  group('slugify', () {
    test('lowercases, strips punctuation and hyphenates', () {
      expect(slugify('Hello, World!'), 'hello-world');
    });
  });
}
