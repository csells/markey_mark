import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';
import 'package:markey_mark/src/editing/delta_ot.dart';
import 'package:markey_mark/src/model/persistent_list.dart';

/// Targeted coverage for pure value-types and helpers (toString / copyWith /
/// equality / edge branches) that the behavioural tests don't exercise.
void main() {
  group('Node value semantics (copyWith / == / hashCode / toString)', () {
    void check(Node a, Node sameAsA, Node different) {
      expect(a, sameAsA);
      expect(a.hashCode, sameAsA.hashCode);
      expect(a, isNot(different));
      expect(a.toString(), isNotEmpty);
      expect(a.copyWith(attributes: const {'x': 1}).id, a.id);
    }

    test('HtmlBlockNode', () => check(HtmlBlockNode(id: 'h', html: '<b>'),
        HtmlBlockNode(id: 'h', html: '<b>'), HtmlBlockNode(id: 'h', html: '<i>')));
    test('CustomBlockNode', () => check(
        CustomBlockNode(id: 'c', blockType: 't', data: const {'n': 1}),
        CustomBlockNode(id: 'c', blockType: 't', data: const {'n': 1}),
        CustomBlockNode(id: 'c', blockType: 't', data: const {'n': 2})));
    test('MathBlockNode', () => check(MathBlockNode(id: 'm', tex: 'x'),
        MathBlockNode(id: 'm', tex: 'x'), MathBlockNode(id: 'm', tex: 'y')));
    test('MermaidNode', () => check(MermaidNode(id: 'd', source: 'a'),
        MermaidNode(id: 'd', source: 'a'), MermaidNode(id: 'd', source: 'b')));
    test('FrontMatterNode', () => check(FrontMatterNode(id: 'f', yaml: 'a: 1'),
        FrontMatterNode(id: 'f', yaml: 'a: 1'),
        FrontMatterNode(id: 'f', yaml: 'a: 2')));
    test('ImageNode', () => check(ImageNode(id: 'i', url: 'a.png', alt: 'a'),
        ImageNode(id: 'i', url: 'a.png', alt: 'a'),
        ImageNode(id: 'i', url: 'b.png')));
    test('CodeBlockNode', () => check(CodeBlockNode(id: 'k', code: 'x'),
        CodeBlockNode(id: 'k', code: 'x'), CodeBlockNode(id: 'k', code: 'y')));
    test('HorizontalRuleNode', () {
      final r = HorizontalRuleNode(id: 'r');
      expect(r.type, BlockType.horizontalRule);
      expect(r.copyWith(attributes: const {}).id, 'r');
    });
    test('TableNode copyWith + withCell + cellText', () {
      final t = TableNode(id: 't', rows: [
        [Delta.text('a'), Delta.text('b')]
      ], alignments: const [TableAlign.none, TableAlign.center]);
      expect(t.cellText(0, 1), 'b');
      expect(t.withCell(0, 0, Delta.text('Z')).cellText(0, 0), 'Z');
      expect(t.copyWith(attributes: const {'x': 1}).id, 't');
      expect(t.toString(), contains('Table'));
    });
  });

  group('DroppedItem (non-const) + DropKind', () {
    test('text + image items execute their constructors', () {
      // Non-const on purpose: a const construction is compile-time and wouldn't
      // execute (cover) the constructor body.
      // ignore: prefer_const_constructors
      final t = DroppedItem.text('hi');
      // ignore: prefer_const_constructors
      final i = DroppedItem.image('p.png', alt: 'a');
      expect(t.kind, DropKind.text);
      expect(i.kind, DropKind.image);
      expect(DropKind.values, contains(DropKind.image));
    });
  });

  group('PersistentList', () {
    test('isEmpty / empty', () {
      expect(PersistentList<int>.empty().isEmpty, isTrue);
      expect(PersistentList<int>.of([1]).isEmpty, isFalse);
    });
  });

  group('EditorStyle.copyWith covers every field', () {
    test('copyWith replaces all fields', () {
      final base = EditorStyle.fromTheme(ThemeData.light());
      final copy = base.copyWith(
        baseTextStyle: const TextStyle(fontSize: 99),
        headingStyles: const {1: TextStyle(fontSize: 40)},
        codeTextStyle: const TextStyle(fontSize: 11),
        linkColor: const Color(0xFF112233),
        selectionColor: const Color(0xFF223344),
        caretColor: const Color(0xFF334455),
        highlightColor: const Color(0xFF445566),
        padding: const EdgeInsets.all(3),
        blockSpacing: 7,
      );
      expect(copy.baseTextStyle.fontSize, 99);
      expect(copy.highlightColor, const Color(0xFF445566));
      expect(copy.blockSpacing, 7);
      expect(copy.headingStyle(1).fontSize, 40);
    });
  });

  group('OtCollaborationSession getters', () {
    test('peers / isActive / dispose', () {
      final a = MarkdownEditorController(markdown: 'x');
      final b = MarkdownEditorController(markdown: 'x');
      final s = OtCollaborationSession([a, b]);
      expect(s.peers, [a, b]);
      expect(s.isActive, isTrue);
      s.dispose();
      expect(s.isActive, isFalse);
      s.dispose(); // idempotent
      a.dispose();
      b.dispose();
    });
  });

  group('DeltaChange edges', () {
    test('adjacent inserts merge; toString is non-empty', () {
      final change = DeltaChange.diff(Delta.text('a'), Delta.text('aXY'));
      expect(change.applyTo(Delta.text('a')), Delta.text('aXY'));
      expect(change.toString(), contains('DeltaChange'));
    });
  });

  group('DocumentText edges', () {
    test('positionAt throws on a stream with no text segments', () {
      final doc = Document([ImageNode(id: 'i', url: 'a.png')]);
      final dt = DocumentText.of(doc);
      expect(dt.coversAny, isFalse);
      expect(() => dt.positionAt(0), throwsStateError);
    });
  });
}
