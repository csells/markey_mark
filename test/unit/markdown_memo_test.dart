import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// The `markdown` getter must be O(1) on repeat — serialization is cached by
/// document identity, so reading it many times (autosave listener + onChanged +
/// callers) doesn't re-serialize the whole document each time.
void main() {
  test('reading markdown repeatedly serializes only once per document', () {
    final c = MarkdownEditorController(markdown: '# Title\n\nbody');
    Markdown.debugSerializeCount = 0;
    final a = c.markdown;
    final b = c.markdown;
    final d = c.markdown;
    expect(a, b);
    expect(b, d);
    expect(Markdown.debugSerializeCount, 1, reason: 'memoized by doc identity');
    c.dispose();
  });

  test('an edit invalidates the cache (one more serialize after a change)', () {
    final c = MarkdownEditorController(markdown: 'abc');
    final id = c.document.nodes.first.id;
    c.markdown; // prime
    Markdown.debugSerializeCount = 0;
    c.placeCaretAt(DocumentPosition.text(id, 3));
    c.insertText('d');
    final after = c.markdown;
    final again = c.markdown;
    expect(after, 'abcd');
    expect(again, after);
    expect(Markdown.debugSerializeCount, 1, reason: 're-serialize once per change');
    c.dispose();
  });
}
