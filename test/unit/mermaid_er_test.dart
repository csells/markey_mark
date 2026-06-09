import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/diagram/mermaid_er.dart';

void main() {
  group('parseEntityRelationship', () {
    test('parses entities and relationships', () {
      final d = parseEntityRelationship(
          'erDiagram\nCUSTOMER ||--o{ ORDER : places\nORDER ||--|{ LINE_ITEM : contains');
      expect(d, isNotNull);
      expect(d!.classes.keys, containsAll(['CUSTOMER', 'ORDER', 'LINE_ITEM']));
      final r = d.relations
          .firstWhere((e) => e.from == 'CUSTOMER' && e.to == 'ORDER');
      expect(r.label, 'places');
    });

    test('parses entity attribute blocks', () {
      final d = parseEntityRelationship(
          'erDiagram\nCUSTOMER {\nstring name\nint age\n}')!;
      expect(d.classes['CUSTOMER']!.members, ['string name', 'int age']);
    });

    test('returns null for non-ER diagrams', () {
      expect(parseEntityRelationship('classDiagram\nA <|-- B'), isNull);
      expect(parseEntityRelationship('graph TD\nA-->B'), isNull);
    });
  });
}
