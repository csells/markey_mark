import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Off-main-thread parsing: `Markdown.parseAsync` runs the decoder in a
/// background isolate (so a large initial load doesn't jank the UI) and yields
/// the same document as the synchronous [Markdown.parse].
void main() {
  test('parseAsync yields the same document as parse', () async {
    const md = '# Title\n\nA paragraph with **bold** and `code`.\n\n- a\n- b';
    final async = await Markdown.parseAsync(md);
    final sync = Markdown.parse(md);
    expect(Markdown.serialize(async), Markdown.serialize(sync));
    expect(async.nodes.first, isA<TextBlockNode>());
    expect((async.nodes.first as TextBlockNode).type, BlockType.heading);
  });

  test('parseAsync handles a large document', () async {
    final big = List.generate(500, (i) => '## Section $i\n\nBody $i.').join('\n\n');
    final doc = await Markdown.parseAsync(big);
    expect(doc.nodes.whereType<TextBlockNode>().length, greaterThan(500));
  });
}
