import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Custom (plugin) blocks round-trip through Markdown via a registered
/// [CustomBlockCodec] — the decode/encode half of the open block set, pairing
/// with the render-side BlockRegistry.
void main() {
  final codecs = BlockCodecs([
    CustomBlockCodec(
      blockType: 'chart',
      fence: 'chart',
      decode: (content) => {'spec': content},
      encode: (node) => node.data['spec'] as String,
    ),
  ]);

  test('a fenced block with a registered info string decodes to a CustomBlock',
      () {
    final doc = Markdown.parse('```chart\nbar: 1,2,3\n```', codecs: codecs);
    expect(doc.nodes.first, isA<CustomBlockNode>());
    final node = doc.nodes.first as CustomBlockNode;
    expect(node.blockType, 'chart');
    expect(node.data['spec'], 'bar: 1,2,3');
  });

  test('a CustomBlock serializes back to its fenced form (round-trip)', () {
    const md = '```chart\nbar: 1,2,3\n```';
    final doc = Markdown.parse(md, codecs: codecs);
    expect(Markdown.serialize(doc, codecs: codecs).trim(), md);
  });

  test('a full round-trip preserves surrounding content', () {
    const md = '# Title\n\n```chart\npie: a,b\n```\n\nAfter.';
    final doc = Markdown.parse(md, codecs: codecs);
    expect(doc.nodes.whereType<CustomBlockNode>().length, 1);
    final out = Markdown.serialize(doc, codecs: codecs);
    expect(out, contains('```chart\npie: a,b\n```'));
    expect(out, contains('# Title'));
    expect(out, contains('After.'));
  });

  test('without the codec, the same fence stays an ordinary code block', () {
    final doc = Markdown.parse('```chart\nx\n```');
    expect(doc.nodes.first, isA<CodeBlockNode>());
    expect((doc.nodes.first as CodeBlockNode).language, 'chart');
  });

  test('BlockCodecs lookup by fence and type', () {
    expect(codecs.byFence('chart')?.blockType, 'chart');
    expect(codecs.byFence('nope'), isNull);
    expect(codecs.byType('chart')?.fence, 'chart');
    expect(const BlockCodecs().isEmpty, isTrue);
  });
}
