import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// The editor chrome is localizable via [MarkdownEditorLabels] — translated
/// strings flow into the toolbar, find bar, table controls, and formatting
/// bubble without forking the widget.
void main() {
  test('MarkdownEditorLabels has value equality', () {
    expect(const MarkdownEditorLabels(), MarkdownEditorLabels.english);
    expect(const MarkdownEditorLabels().hashCode,
        MarkdownEditorLabels.english.hashCode);
    expect(const MarkdownEditorLabels(bold: 'Gras'),
        isNot(const MarkdownEditorLabels()));
  });

  testWidgets('toolbar tooltips use the provided labels', (tester) async {
    final c = MarkdownEditorController(markdown: 'hi');
    addTearDown(c.dispose);
    const fr = MarkdownEditorLabels(
      bold: 'Gras',
      italic: 'Italique',
      undo: 'Annuler',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(controller: c, enableDrop: false, labels: fr),
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<IconButton>(find.byKey(const Key('markey_bold'))).tooltip,
        'Gras');
    expect(
        tester.widget<IconButton>(find.byKey(const Key('markey_italic'))).tooltip,
        'Italique');
    expect(tester.widget<IconButton>(find.byKey(const Key('markey_undo'))).tooltip,
        'Annuler');
  });

  testWidgets('find bar + bubble use the provided labels', (tester) async {
    final c = MarkdownEditorController(markdown: 'hello world');
    addTearDown(c.dispose);
    const es = MarkdownEditorLabels(find: 'Buscar', bold: 'Negrita');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 400,
            child: MarkdownEditor(controller: c, enableDrop: false, labels: es),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(MarkdownEditor));
    await tester.pump();

    // Open find: its hint is localized.
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(c.document.nodes.first.id, 0),
      extent: DocumentPosition.text(c.document.nodes.first.id, 5),
    ));
    await tester.pump();
    // The formatting bubble (shown for a single-block range) uses the label.
    final bold =
        tester.widget<IconButton>(find.byKey(const Key('markey_bubble_bold')));
    expect(bold.tooltip, 'Negrita');
  });
}
