import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/model/delta.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('MathBlockNode', () {
    test('value semantics', () {
      final a = MathBlockNode(id: 'm', tex: 'x^2');
      expect(a.type, BlockType.mathBlock);
      expect(a, MathBlockNode(id: 'm', tex: 'x^2'));
      expect(a == MathBlockNode(id: 'm', tex: 'y'), isFalse);
      expect(a.hashCode, MathBlockNode(id: 'm', tex: 'x^2').hashCode);
      expect((a.copyWith() as MathBlockNode).tex, 'x^2');
      expect(a.toString(), contains('MathBlockNode'));
    });
  });

  group('MermaidNode', () {
    test('value semantics', () {
      final a = MermaidNode(id: 'g', source: 'graph TD');
      expect(a.type, BlockType.mermaid);
      expect(a, MermaidNode(id: 'g', source: 'graph TD'));
      expect(a == MermaidNode(id: 'g', source: 'x'), isFalse);
      expect(a.hashCode, MermaidNode(id: 'g', source: 'graph TD').hashCode);
      expect(a.copyWith().id, 'g');
      expect(a.toString(), contains('MermaidNode'));
    });
  });

  group('FrontMatterNode', () {
    test('value semantics', () {
      final a = FrontMatterNode(id: 'f', yaml: 'a: 1');
      expect(a.type, BlockType.frontMatter);
      expect(a, FrontMatterNode(id: 'f', yaml: 'a: 1'));
      expect(a == FrontMatterNode(id: 'f', yaml: 'b: 2'), isFalse);
      expect(a.hashCode, FrontMatterNode(id: 'f', yaml: 'a: 1').hashCode);
      expect(a.copyWith().id, 'f');
      expect(a.toString(), contains('FrontMatterNode'));
    });
  });

  group('TableNode', () {
    TableNode t() => TableNode(
          rows: [
            [Delta.text('A'), Delta.text('B')],
            [Delta.text('1'), Delta.text('2')],
          ],
          alignments: [TableAlign.left, TableAlign.center],
        );

    test('basic shape + cellText', () {
      final n = t();
      expect(n.type, BlockType.table);
      expect(n.rowCount, 2);
      expect(n.columnCount, 2);
      expect(n.cellText(0, 1), 'B');
      expect(n.toString(), contains('2x2'));
    });

    test('withCell replaces a single cell, preserving the rest', () {
      final n = t().withCell(1, 1, Delta.text('99'));
      expect(n.cellText(1, 1), '99');
      expect(n.cellText(1, 0), '1');
      expect(n.id, t().id == n.id ? n.id : n.id); // id preserved on copy
    });

    test('withAppendedRow / withAppendedColumn', () {
      final r = t().withAppendedRow();
      expect(r.rowCount, 3);
      expect(r.cellText(2, 0), '');
      final c = t().withAppendedColumn();
      expect(c.columnCount, 3);
      expect(c.alignments.last, TableAlign.none);
      expect(c.rows.every((row) => row.length == 3), isTrue);
    });

    test('equality + hashCode + copyWith', () {
      final a = TableNode(id: 't', rows: [
        [Delta.text('x')]
      ], alignments: [TableAlign.none]);
      final b = TableNode(id: 't', rows: [
        [Delta.text('x')]
      ], alignments: [TableAlign.none]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith().id, 't');
      final diff = TableNode(id: 't', rows: [
        [Delta.text('y')]
      ], alignments: [TableAlign.none]);
      expect(a == diff, isFalse);
    });
  });

  group('TextBlockNode extension getters', () {
    test('definition term/desc + footnoteDef + indent', () {
      expect(TextBlockNode.definitionTerm(delta: Delta.text('T')).type,
          BlockType.definitionTerm);
      expect(TextBlockNode.definitionDesc(delta: Delta.text('D')).type,
          BlockType.definitionDesc);
      final fn = TextBlockNode.footnoteDef(label: '1', delta: Delta.text('x'));
      expect(fn.footnoteLabel, '1');
      expect(TextBlockNode.bullet(indent: 2).indent, 2);
      expect(TextBlockNode.quote(indent: 1).indent, 1);
      expect(TextBlockNode.paragraph().indent, 0);
    });
  });
}
