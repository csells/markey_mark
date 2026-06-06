import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_class.dart';

void main() {
  group('parseClassDiagram', () {
    test('parses relations with kinds', () {
      final d = parseClassDiagram(
          'classDiagram\nAnimal <|-- Dog\nAnimal <|-- Cat\nDog --> Bone');
      expect(d, isNotNull);
      expect(d!.classes.keys, containsAll(['Animal', 'Dog', 'Cat', 'Bone']));
      final inh = d.relations
          .firstWhere((r) => r.from == 'Animal' && r.to == 'Dog');
      expect(inh.kind, ClassRelationKind.inheritance);
      final assoc =
          d.relations.firstWhere((r) => r.from == 'Dog' && r.to == 'Bone');
      expect(assoc.kind, ClassRelationKind.association);
    });

    test('parses class member blocks', () {
      final d = parseClassDiagram(
          'classDiagram\nclass Animal {\n+String name\n+makeSound()\n}')!;
      expect(d.classes['Animal']!.members, ['+String name', '+makeSound()']);
    });

    test('parses inline members (Name : member)', () {
      final d = parseClassDiagram('classDiagram\nAnimal : +int age')!;
      expect(d.classes['Animal']!.members, ['+int age']);
    });

    test('returns null for non-class diagrams', () {
      expect(parseClassDiagram('graph TD\nA-->B'), isNull);
      expect(parseClassDiagram('pie\n"A":1'), isNull);
    });

    test('returns null when empty', () {
      expect(parseClassDiagram('classDiagram'), isNull);
    });
  });
}
