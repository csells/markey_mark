import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  String text(d) => (d.nodes.first as TextBlockNode).delta.toPlainText();

  group('Emoji shortcodes', () {
    test(':heart: becomes an emoji glyph', () {
      final d = Markdown.parse('I :heart: Flutter');
      final t = text(d);
      expect(t.contains(':heart:'), isFalse);
      expect(t.runes.any((r) => r > 0x2000), isTrue); // a non-ascii emoji
    });

    test('unknown shortcodes are left as-is', () {
      final d = Markdown.parse('a :not_an_emoji_xyz: b');
      expect(text(d), contains(':not_an_emoji_xyz:'));
    });

    test('round-trips (emoji glyph is stable)', () {
      final once = Markdown.serialize(Markdown.parse('go :rocket: go'));
      final twice = Markdown.serialize(Markdown.parse(once));
      expect(twice, once);
    });
  });
}
