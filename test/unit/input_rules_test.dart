import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/editing/input_rules.dart';
import 'package:markey_mark/src/model/delta.dart';
import 'package:markey_mark/src/model/document.dart';
import 'package:markey_mark/src/model/node.dart';
import 'package:markey_mark/src/model/position.dart';
import 'package:markey_mark/src/model/selection.dart';

void main() {
  DocumentSelection caret(String id, int o) =>
      DocumentSelection.collapsed(DocumentPosition.text(id, o));

  TextBlockNode blockOf(Document d, String id) => d.nodeById(id) as TextBlockNode;

  group('HeadingInputRule', () {
    test('converts "# " to a heading and strips the prefix', () {
      final doc = Document([
        TextBlockNode.paragraph(id: 'a', delta: Delta.text('## ')),
      ]);
      final txn = const HeadingInputRule().match(doc, caret('a', 3))!;
      final after = txn.apply(doc);
      final node = blockOf(after, 'a');
      expect(node.type, BlockType.heading);
      expect(node.level, 2);
      expect(node.delta.toPlainText(), '');
      expect(txn.tag, 'input-rule');
      expect(txn.selectionAfter, caret('a', 0));
    });

    test('keeps trailing text after the prefix', () {
      final doc = Document([
        TextBlockNode.paragraph(id: 'a', delta: Delta.text('# Title')),
      ]);
      // Caret right after "# ".
      final txn = const HeadingInputRule().match(doc, caret('a', 2))!;
      final node = blockOf(txn.apply(doc), 'a');
      expect(node.level, 1);
      expect(node.delta.toPlainText(), 'Title');
    });

    test('does not fire on a non-paragraph', () {
      final doc = Document([
        TextBlockNode.heading(id: 'a', level: 1, delta: Delta.text('# ')),
      ]);
      expect(const HeadingInputRule().match(doc, caret('a', 2)), isNull);
    });

    test('does not fire without trailing space', () {
      final doc = Document([
        TextBlockNode.paragraph(id: 'a', delta: Delta.text('#')),
      ]);
      expect(const HeadingInputRule().match(doc, caret('a', 1)), isNull);
    });

    test('does not fire on more than 6 hashes', () {
      final doc = Document([
        TextBlockNode.paragraph(id: 'a', delta: Delta.text('####### ')),
      ]);
      expect(const HeadingInputRule().match(doc, caret('a', 8)), isNull);
    });
  });

  group('WrapInputRule (bold/italic/strike/code)', () {
    Document para(String text) =>
        Document([TextBlockNode.paragraph(id: 'a', delta: Delta.text(text))]);

    test('**x** becomes bold', () {
      final doc = para('**hi**');
      final txn = applyInputRules(doc, caret('a', 6), rules: defaultInputRules)!;
      final node = blockOf(txn.apply(doc), 'a');
      expect(node.delta.toPlainText(), 'hi');
      expect(node.delta.runs.single.attributes, {'bold': true});
    });

    test('_x_ becomes italic', () {
      final doc = para('_hi_');
      final txn = applyInputRules(doc, caret('a', 4), rules: defaultInputRules)!;
      final node = blockOf(txn.apply(doc), 'a');
      expect(node.delta.runs.single.attributes, {'italic': true});
    });

    test('~~x~~ becomes strike', () {
      final doc = para('~~hi~~');
      final txn = applyInputRules(doc, caret('a', 6), rules: defaultInputRules)!;
      expect(blockOf(txn.apply(doc), 'a').delta.runs.single.attributes,
          {'strike': true});
    });

    test('`x` becomes code', () {
      final doc = para('`hi`');
      final txn = applyInputRules(doc, caret('a', 4), rules: defaultInputRules)!;
      expect(blockOf(txn.apply(doc), 'a').delta.runs.single.attributes,
          {'code': true});
    });

    test('empty content does not match', () {
      final doc = para('****');
      expect(applyInputRules(doc, caret('a', 4), rules: defaultInputRules), isNull);
    });

    test('caret moves to end of unwrapped content', () {
      final doc = para('x**hi**');
      final txn = applyInputRules(doc, caret('a', 7), rules: defaultInputRules)!;
      // 'x' + 'hi' = 3 chars.
      expect(txn.selectionAfter, caret('a', 3));
    });
  });

  group('applyInputRules', () {
    test('returns null with no selection', () {
      final doc = Document.empty();
      expect(applyInputRules(doc, null, rules: defaultInputRules), isNull);
    });

    test('returns null when nothing matches', () {
      final doc =
          Document([TextBlockNode.paragraph(id: 'a', delta: Delta.text('plain'))]);
      expect(applyInputRules(doc, caret('a', 5), rules: defaultInputRules), isNull);
    });

    test('default rule set is non-empty and ordered (heading first)', () {
      expect(defaultInputRules, isNotEmpty);
      expect(defaultInputRules.first, isA<HeadingInputRule>());
    });
  });
}
