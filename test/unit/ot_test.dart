import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  TextBlockNode p(String id, String text) =>
      TextBlockNode.paragraph(id: id, delta: Delta.text(text));

  String text(Document d, int i) =>
      (d.nodes[i] as TextBlockNode).delta.toPlainText();

  group('transformOperation — index transforms', () {
    test('a concurrent insert before shifts a later op down', () {
      final op = ReplaceNodeOp(1, p('b', 'b'), p('b', 'B'));
      final against = InsertNodeOp(0, p('x', 'x'));
      final t = transformOperation(op, against, tieBreak: true)!;
      expect((t as ReplaceNodeOp).index, 2);
    });

    test('a concurrent delete before shifts a later op up', () {
      final op = ReplaceNodeOp(2, p('c', 'c'), p('c', 'C'));
      final against = DeleteNodeOp(0, p('a', 'a'));
      final t = transformOperation(op, against, tieBreak: true)!;
      expect((t as ReplaceNodeOp).index, 1);
    });

    test('replacing a node deleted concurrently becomes a no-op', () {
      final op = ReplaceNodeOp(1, p('b', 'b'), p('b', 'B'));
      final against = DeleteNodeOp(1, p('b', 'b'));
      expect(transformOperation(op, against, tieBreak: true), isNull);
    });
  });

  group('transformOperation — same-node conflict', () {
    test('the winner rebases its before onto the loser\'s result', () {
      final mine = ReplaceNodeOp(0, p('a', 'base'), p('a', 'MINE'));
      final theirs = ReplaceNodeOp(0, p('a', 'base'), p('a', 'theirs'));
      // mine wins → rebased onto theirs.after so it applies cleanly.
      final t = transformOperation(mine, theirs, tieBreak: true)! as ReplaceNodeOp;
      expect((t.before as TextBlockNode).delta.toPlainText(), 'theirs');
      expect((t.after as TextBlockNode).delta.toPlainText(), 'MINE');
      // loser is dropped.
      expect(transformOperation(theirs, mine, tieBreak: false), isNull);
    });
  });

  group('convergence (TP1)', () {
    // Both peers must reach the same document regardless of apply order.
    void expectConverges(Document base, EditTransaction a, EditTransaction b,
        {required bool aWins}) {
      // Peer 1: applies a, then receives b (transformed against a).
      final p1 = transformTransaction(b, a, tieBreak: !aWins).apply(a.apply(base));
      // Peer 2: applies b, then receives a (transformed against b).
      final p2 = transformTransaction(a, b, tieBreak: aWins).apply(b.apply(base));
      expect(p1.nodes.map((n) => n is TextBlockNode ? n.delta.toPlainText() : n.type).toList(),
          p2.nodes.map((n) => n is TextBlockNode ? n.delta.toPlainText() : n.type).toList());
    }

    EditTransaction txn(List<Operation> ops) => EditTransaction(operations: ops);

    test('concurrent insert + edit on different blocks converge', () {
      final base = Document([p('a', 'a'), p('b', 'b')]);
      final a = txn([InsertNodeOp(1, p('x', 'x'))]);
      final b = txn([ReplaceNodeOp(1, p('b', 'b'), p('b', 'B'))]);
      expectConverges(base, a, b, aWins: true);
    });

    test('concurrent edits to the same block converge to the winner', () {
      final base = Document([p('a', 'base')]);
      final a = txn([ReplaceNodeOp(0, p('a', 'base'), p('a', 'AAA'))]);
      final b = txn([ReplaceNodeOp(0, p('a', 'base'), p('a', 'BBB'))]);
      expectConverges(base, a, b, aWins: true);

      final p1 = transformTransaction(b, a, tieBreak: false).apply(a.apply(base));
      expect(text(p1, 0), 'AAA'); // a won
    });

    test('concurrent deletes of the same block converge', () {
      final base = Document([p('a', 'a'), p('b', 'b')]);
      final a = txn([DeleteNodeOp(0, p('a', 'a'))]);
      final b = txn([DeleteNodeOp(0, p('a', 'a'))]);
      expectConverges(base, a, b, aWins: true);
    });
  });

  group('end-to-end: two diverged controllers reconcile via OT', () {
    test('concurrent same-block edits converge through applyRemote', () {
      // Two peers start from the same document but edit it concurrently
      // (offline), then exchange their transactions transformed against the
      // local one — both must end up identical.
      final a = MarkdownEditorController(markdown: 'base');
      final b = MarkdownEditorController(markdown: 'base');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final aId = a.document.nodes.first.id;
      final bId = b.document.nodes.first.id;
      final aTxn = EditTransaction(operations: [
        ReplaceNodeOp(0, a.document.nodes.first,
            TextBlockNode.paragraph(id: aId, delta: Delta.text('AAA'))),
      ]);
      final bTxn = EditTransaction(operations: [
        ReplaceNodeOp(0, b.document.nodes.first,
            TextBlockNode.paragraph(id: bId, delta: Delta.text('BBB'))),
      ]);

      // Each peer applies its own edit locally...
      a.applyRemote(aTxn);
      b.applyRemote(bTxn);
      expect(a.markdown, 'AAA');
      expect(b.markdown, 'BBB');

      // ...then receives the other's edit, transformed against its own. Peer a
      // wins the deterministic tie-break.
      a.applyRemote(transformTransaction(bTxn, aTxn, tieBreak: false));
      b.applyRemote(transformTransaction(aTxn, bTxn, tieBreak: true));

      expect(a.markdown, b.markdown);
      expect(a.markdown, 'AAA');
    });
  });
}
