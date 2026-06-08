import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Value-type coverage for the position model and the document-text stream's
/// error paths.
void main() {
  group('AtomicNodePosition', () {
    test('upstream/downstream + equality + hashCode + toString', () {
      const up = AtomicNodePosition.upstream();
      const down = AtomicNodePosition.downstream();
      expect(up.upstream, isTrue);
      expect(down.upstream, isFalse);
      expect(up, const AtomicNodePosition.upstream());
      expect(up.hashCode, const AtomicNodePosition.upstream().hashCode);
      expect(up, isNot(down));
      expect(up.toString(), contains('upstream'));
    });
  });

  group('TableCellPosition', () {
    test('equality, hashCode, copyWith, toString', () {
      const p = TableCellPosition(1, 2, 3);
      expect(p, const TableCellPosition(1, 2, 3));
      expect(p.hashCode, const TableCellPosition(1, 2, 3).hashCode);
      expect(p, isNot(const TableCellPosition(1, 2, 4)));
      expect(p.copyWith(offset: 9), const TableCellPosition(1, 2, 9));
      expect(p.copyWith(row: 5, col: 6),
          const TableCellPosition(5, 6, 3));
      expect(p.toString(), 'TableCellPosition(1, 2, 3)');
    });
  });

  group('DocumentPosition', () {
    test('copyWith replaces nodeId / nodePosition', () {
      final p = DocumentPosition.text('a', 1);
      final q = p.copyWith(nodeId: 'b');
      expect(q.nodeId, 'b');
      expect((q.nodePosition as TextNodePosition).offset, 1);
      final r = p.copyWith(nodePosition: const TextNodePosition(5));
      expect(r.nodeId, 'a');
      expect((r.nodePosition as TextNodePosition).offset, 5);
    });
  });

  group('DocumentText error paths', () {
    test('offsetOf throws for a node not in the stream', () {
      final doc = Document([
        TextBlockNode.paragraph(id: 'a', delta: Delta.text('hi')),
      ]);
      final dt = DocumentText.of(doc);
      expect(
        () => dt.offsetOf(DocumentPosition.text('missing', 0)),
        throwsArgumentError,
      );
    });
  });
}
