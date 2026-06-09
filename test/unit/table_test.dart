import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/markdown/markdown.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('Table markdown', () {
    const md = '| Name | Age |\n| --- | --- |\n| Ann | 30 |\n| Bob | 25 |';

    test('decodes header + rows + dimensions', () {
      final d = Markdown.parse(md);
      final t = d.nodes.first as TableNode;
      expect(t.columnCount, 2);
      expect(t.rowCount, 3); // header + 2 body rows
      expect(t.cellText(0, 0), 'Name');
      expect(t.cellText(0, 1), 'Age');
      expect(t.cellText(1, 0), 'Ann');
      expect(t.cellText(2, 1), '25');
    });

    test('decodes column alignments', () {
      final d = Markdown.parse('| L | C | R |\n| :-- | :-: | --: |\n| a | b | c |');
      final t = d.nodes.first as TableNode;
      expect(t.alignments[0], TableAlign.left);
      expect(t.alignments[1], TableAlign.center);
      expect(t.alignments[2], TableAlign.right);
    });

    test('round-trips', () {
      final once = Markdown.serialize(Markdown.parse(md));
      final twice = Markdown.serialize(Markdown.parse(once));
      expect(twice, once);
      // And the structure is stable.
      final t = Markdown.parse(once).nodes.first as TableNode;
      expect(t.columnCount, 2);
      expect(t.rowCount, 3);
    });

    test('preserves inline marks inside cells', () {
      final d = Markdown.parse('| h |\n| --- |\n| **bold** |');
      final t = d.nodes.first as TableNode;
      expect(t.rows[1][0].isFormatted(0, 4, 'bold'), isTrue);
    });
  });
}
