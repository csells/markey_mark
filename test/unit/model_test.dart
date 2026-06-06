import 'package:flutter/painting.dart' show TextAffinity;
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/model/delta.dart';
import 'package:markey_mark/src/model/document.dart';
import 'package:markey_mark/src/model/node.dart';
import 'package:markey_mark/src/model/position.dart';
import 'package:markey_mark/src/model/selection.dart';

void main() {
  group('NodeIds', () {
    test('generates unique ids', () {
      final ids = {for (var i = 0; i < 1000; i++) NodeIds.next()};
      expect(ids.length, 1000);
    });
  });

  group('TextBlockNode', () {
    test('paragraph factory', () {
      final p = TextBlockNode.paragraph();
      expect(p.type, BlockType.paragraph);
      expect(p.delta.isEmpty, isTrue);
      expect(p.level, isNull);
    });

    test('heading factory carries level', () {
      final h = TextBlockNode.heading(level: 2, delta: Delta.text('Hi'));
      expect(h.type, BlockType.heading);
      expect(h.level, 2);
      expect(h.delta.toPlainText(), 'Hi');
    });

    test('copyWithDelta keeps id and type', () {
      final h = TextBlockNode.heading(level: 1, delta: Delta.text('a'));
      final h2 = h.copyWithDelta(Delta.text('b'));
      expect(h2.id, h.id);
      expect(h2.type, h.type);
      expect(h2.level, 1);
      expect(h2.delta.toPlainText(), 'b');
    });

    test('asType converts preserving id and delta', () {
      final p = TextBlockNode.paragraph(delta: Delta.text('x'));
      final h = p.asType(BlockType.heading, level: 3);
      expect(h.id, p.id);
      expect(h.type, BlockType.heading);
      expect(h.level, 3);
      expect(h.delta.toPlainText(), 'x');
      final back = h.asType(BlockType.paragraph);
      expect(back.level, isNull);
    });

    test('copyWith changes attributes/delta', () {
      final p = TextBlockNode.paragraph(delta: Delta.text('a'));
      final p2 = p.copyWith(delta: Delta.text('b'));
      expect(p2.delta.toPlainText(), 'b');
      expect(p2.id, p.id);
    });

    test('equality and hashCode', () {
      final a = TextBlockNode.paragraph(id: 'x', delta: Delta.text('hi'));
      final b = TextBlockNode.paragraph(id: 'x', delta: Delta.text('hi'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == TextBlockNode.paragraph(id: 'y', delta: Delta.text('hi')),
          isFalse);
    });

    test('toString includes heading level', () {
      expect(
        TextBlockNode.heading(level: 2, delta: Delta.text('a')).toString(),
        contains('h2'),
      );
    });
  });

  group('Document', () {
    test('empty contains one paragraph', () {
      final d = Document.empty();
      expect(d.length, 1);
      expect(d.isEmpty, isTrue);
    });

    test('constructing with empty list yields a paragraph', () {
      expect(Document([]).length, 1);
    });

    test('lookup by id and index', () {
      final a = TextBlockNode.paragraph(id: 'a', delta: Delta.text('A'));
      final b = TextBlockNode.paragraph(id: 'b', delta: Delta.text('B'));
      final d = Document([a, b]);
      expect(d.nodeById('a'), a);
      expect(d.nodeById('missing'), isNull);
      expect(d.indexOfId('b'), 1);
      expect(d.indexOfId('missing'), -1);
      expect(d.isEmpty, isFalse);
    });

    test('before/after navigation', () {
      final a = TextBlockNode.paragraph(id: 'a');
      final b = TextBlockNode.paragraph(id: 'b');
      final d = Document([a, b]);
      expect(d.nodeBefore('b'), a);
      expect(d.nodeBefore('a'), isNull);
      expect(d.nodeAfter('a'), b);
      expect(d.nodeAfter('b'), isNull);
    });

    test('insert/remove/replace return new documents', () {
      final a = TextBlockNode.paragraph(id: 'a');
      final b = TextBlockNode.paragraph(id: 'b');
      var d = Document([a]);
      d = d.insertAt(1, b);
      expect(d.length, 2);
      d = d.replaceAt(0, TextBlockNode.paragraph(id: 'a', delta: Delta.text('x')));
      expect((d.nodes.first as TextBlockNode).delta.toPlainText(), 'x');
      d = d.replaceById('b', TextBlockNode.paragraph(id: 'b', delta: Delta.text('y')));
      expect((d.nodeById('b') as TextBlockNode).delta.toPlainText(), 'y');
      expect(d.replaceById('missing', a), same(d));
      d = d.removeAt(1);
      expect(d.length, 1);
    });

    test('equality + hashCode + toString', () {
      final a = TextBlockNode.paragraph(id: 'a', delta: Delta.text('A'));
      expect(Document([a]), Document([a]));
      expect(Document([a]).hashCode, Document([a]).hashCode);
      expect(Document([a]).toString(), contains('1 nodes'));
    });
  });

  group('Positions and selection', () {
    test('TextNodePosition equality/copyWith/toString', () {
      const p = TextNodePosition(3);
      expect(p, const TextNodePosition(3));
      expect(p.copyWith(offset: 5), const TextNodePosition(5));
      expect(
        p.copyWith(affinity: TextAffinity.upstream).affinity,
        TextAffinity.upstream,
      );
      expect(p.hashCode, const TextNodePosition(3).hashCode);
      expect(p.toString(), 'TextNodePosition(3)');
    });

    test('AtomicNodePosition upstream/downstream', () {
      const up = AtomicNodePosition.upstream();
      const down = AtomicNodePosition.downstream();
      expect(up == const AtomicNodePosition.upstream(), isTrue);
      expect(up == down, isFalse);
      expect(up.hashCode, const AtomicNodePosition.upstream().hashCode);
      expect(up.toString(), contains('upstream'));
      expect(down.toString(), contains('downstream'));
    });

    test('DocumentPosition.text helper + equality + copyWith', () {
      final p = DocumentPosition.text('n', 2);
      expect(p.nodeId, 'n');
      expect((p.nodePosition as TextNodePosition).offset, 2);
      expect(p, DocumentPosition.text('n', 2));
      expect(p.copyWith(nodeId: 'm').nodeId, 'm');
      expect(p.hashCode, DocumentPosition.text('n', 2).hashCode);
      expect(p.toString(), contains('DocumentPosition'));
    });

    test('DocumentSelection collapsed and copyWith', () {
      final caret = DocumentSelection.collapsed(DocumentPosition.text('n', 1));
      expect(caret.isCollapsed, isTrue);
      final range = DocumentSelection(
        base: DocumentPosition.text('n', 0),
        extent: DocumentPosition.text('n', 3),
      );
      expect(range.isCollapsed, isFalse);
      expect(range.collapseTo(DocumentPosition.text('n', 2)).isCollapsed, isTrue);
      expect(
        range.copyWith(base: DocumentPosition.text('n', 1)).base,
        DocumentPosition.text('n', 1),
      );
      expect(caret.hashCode, isA<int>());
      expect(caret == range, isFalse);
      expect(caret.toString(), contains('DocumentSelection'));
    });
  });
}
