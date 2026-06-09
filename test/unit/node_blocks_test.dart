import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/model/delta.dart';
import 'package:markey_mark/src/model/node.dart';

void main() {
  group('TextBlockNode list/quote factories + getters', () {
    test('bullet', () {
      final n = TextBlockNode.bullet(delta: Delta.text('x'));
      expect(n.type, BlockType.bulletedListItem);
      expect(n.number, isNull);
      expect(n.checked, isNull);
    });

    test('numbered carries number', () {
      final n = TextBlockNode.numbered(number: 3, delta: Delta.text('x'));
      expect(n.type, BlockType.numberedListItem);
      expect(n.number, 3);
    });

    test('todo carries checked (true) and derives false', () {
      expect(TextBlockNode.todo(checked: true).checked, true);
      expect(TextBlockNode.todo().checked, false);
      // checked is null for non-todo types.
      expect(TextBlockNode.bullet().checked, isNull);
    });

    test('quote', () {
      expect(TextBlockNode.quote(delta: Delta.text('q')).type, BlockType.quote);
    });
  });

  group('CodeBlockNode', () {
    test('construction + getters + type', () {
      final n = CodeBlockNode(id: 'c', code: 'x=1', language: 'dart');
      expect(n.type, BlockType.codeBlock);
      expect(n.code, 'x=1');
      expect(n.language, 'dart');
    });

    test('copyWithCode + copyWith preserve id', () {
      final n = CodeBlockNode(id: 'c', code: 'a', language: 'dart');
      expect(n.copyWithCode('b').code, 'b');
      expect(n.copyWithCode('b').id, 'c');
      expect(n.copyWith().id, 'c');
    });

    test('equality, hashCode, toString', () {
      final a = CodeBlockNode(id: 'c', code: 'a', language: 'dart');
      final b = CodeBlockNode(id: 'c', code: 'a', language: 'dart');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == CodeBlockNode(id: 'c', code: 'z', language: 'dart'), isFalse);
      expect(a.toString(), contains('CodeBlockNode'));
    });
  });

  group('HorizontalRuleNode', () {
    test('type + copyWith + equality + toString', () {
      final a = HorizontalRuleNode(id: 'h');
      expect(a.type, BlockType.horizontalRule);
      expect(a.copyWith().id, 'h');
      expect(a, HorizontalRuleNode(id: 'h'));
      expect(a == HorizontalRuleNode(id: 'z'), isFalse);
      expect(a.hashCode, HorizontalRuleNode(id: 'h').hashCode);
      expect(a.toString(), contains('HorizontalRuleNode'));
    });
  });

  group('ImageNode', () {
    test('construction + type + copyWith', () {
      final n = ImageNode(id: 'i', url: 'u', alt: 'a', title: 't');
      expect(n.type, BlockType.image);
      expect(n.url, 'u');
      expect(n.alt, 'a');
      expect(n.title, 't');
      expect(n.copyWith().id, 'i');
    });

    test('equality, hashCode, toString', () {
      final a = ImageNode(id: 'i', url: 'u', alt: 'a');
      expect(a, ImageNode(id: 'i', url: 'u', alt: 'a'));
      expect(a.hashCode, ImageNode(id: 'i', url: 'u', alt: 'a').hashCode);
      expect(a == ImageNode(id: 'i', url: 'v', alt: 'a'), isFalse);
      expect(a.toString(), contains('ImageNode'));
    });
  });
}
