import 'mermaid_class.dart';

final RegExp _first = RegExp(r'^erDiagram(\s|$)');
// ENTITY <cardinality token containing --> ENTITY : label
final RegExp _relation =
    RegExp(r'^([\w-]+)\s+(\S*--\S*)\s+([\w-]+)(?:\s*:\s*(.+))?$');
final RegExp _entityOpen = RegExp(r'^([\w-]+)\s*\{$');

/// Parses a Mermaid `erDiagram` into the shared [ClassDiagram] model (entities
/// as boxes with attributes, relationships as labeled links), so it reuses the
/// native class-diagram renderer. Pure Dart — no JS.
ClassDiagram? parseEntityRelationship(String source) {
  final lines =
      source.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || !_first.hasMatch(lines.first)) return null;

  final classes = <String, ClassBox>{};
  final relations = <ClassRelation>[];
  ClassBox box(String n) => classes.putIfAbsent(n, () => ClassBox(n));

  String? open;
  for (final line in lines.skip(1)) {
    if (open != null) {
      if (line == '}') {
        open = null;
      } else {
        box(open).members.add(line);
      }
      continue;
    }
    final eo = _entityOpen.firstMatch(line);
    if (eo != null) {
      box(eo.group(1)!);
      open = eo.group(1)!;
      continue;
    }
    final r = _relation.firstMatch(line);
    if (r != null) {
      box(r.group(1)!);
      box(r.group(3)!);
      relations.add(ClassRelation(
          r.group(1)!, r.group(3)!, ClassRelationKind.link, r.group(4)?.trim()));
    }
  }
  if (classes.isEmpty) return null;
  return ClassDiagram(classes, relations);
}
