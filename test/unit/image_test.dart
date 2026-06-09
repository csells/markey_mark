import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('Image markdown', () {
    test('decodes a standalone image', () {
      final d = Markdown.parse('![a cat](http://x/cat.png)');
      final img = d.nodes.first as ImageNode;
      expect(img.url, 'http://x/cat.png');
      expect(img.alt, 'a cat');
    });

    test('decodes optional title', () {
      final d = Markdown.parse('![a](http://x.png "Tooltip")');
      expect((d.nodes.first as ImageNode).title, 'Tooltip');
    });

    test('round-trips', () {
      expect(
        Markdown.serialize(Markdown.parse('![alt](http://x/y.png)')),
        '![alt](http://x/y.png)',
      );
    });

    test('round-trips with title', () {
      const md = '![a](http://x.png "T")';
      expect(Markdown.serialize(Markdown.parse(md)), md);
    });
  });
}
