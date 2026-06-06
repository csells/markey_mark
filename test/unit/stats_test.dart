import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  group('documentStats', () {
    test('counts words, characters and blocks across text blocks', () {
      final c = MarkdownEditorController(markdown: '# Title\n\nhello world here');
      final s = c.documentStats();
      expect(s.words, 4); // Title + hello + world + here
      expect(s.blocks, 2); // heading + paragraph
      c.dispose();
    });

    test('word and character counts', () {
      final c = MarkdownEditorController(markdown: 'one two three');
      final s = c.documentStats();
      expect(s.words, 3);
      expect(s.characters, 'one two three'.length);
      expect(s.blocks, 1);
      c.dispose();
    });

    test('ignores empty document text', () {
      final c = MarkdownEditorController();
      final s = c.documentStats();
      expect(s.words, 0);
      expect(s.characters, 0);
      c.dispose();
    });

    test('counts non-text blocks toward the block count', () {
      final c = MarkdownEditorController(markdown: 'a\n\n---\n\nb');
      expect(c.documentStats().blocks, 3);
      c.dispose();
    });
  });
}
