import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// End-to-end UI test: the caret position is preserved when toggling between
/// WYSIWYG and source mode.
void main() {
  testWidgets('caret carries from WYSIWYG into the source field', (tester) async {
    final c = MarkdownEditorController(markdown: '# Title\n\nsome body text');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 600, height: 400, child: MarkdownEditor(controller: c)),
        ),
      ),
    );
    await tester.pump();

    // Put the caret after "some " in the body block.
    final bodyId = c.document.nodes.last.id;
    await tester.tap(find.byKey(ValueKey('markey-block-$bodyId')));
    await tester.pump();
    c.setSelection(
        DocumentSelection.collapsed(DocumentPosition.text(bodyId, 5)));
    await tester.pump();

    // Toggle to source.
    c.toggleMode();
    await tester.pump();

    final field =
        tester.widget<TextField>(find.byKey(const Key('markey_source_field')));
    final caret = field.controller!.selection.baseOffset;
    // "# Title\n\nsome " → offset 14
    expect(caret, 14);
    expect(field.controller!.text.substring(0, caret), '# Title\n\nsome ');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a selection range carries into the source field', (tester) async {
    final c = MarkdownEditorController(markdown: 'hello world');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 600, height: 400, child: MarkdownEditor(controller: c)),
        ),
      ),
    );
    await tester.pump();
    final id = c.document.nodes.first.id;
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(id, 0),
      extent: DocumentPosition.text(id, 5), // "hello"
    ));
    await tester.pump();

    c.toggleMode();
    await tester.pump();
    final field =
        tester.widget<TextField>(find.byKey(const Key('markey_source_field')));
    expect(field.controller!.selection.baseOffset, 0);
    expect(field.controller!.selection.extentOffset, 5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('caret carries from source back into WYSIWYG', (tester) async {
    final c = MarkdownEditorController(markdown: '# Title\n\nsome body text');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
              width: 600, height: 400, child: MarkdownEditor(controller: c)),
        ),
      ),
    );
    await tester.pump();

    c.toggleMode(); // to source
    await tester.pump();

    // Move the caret in the source field to inside the body line ("some bo|dy").
    final fieldFinder = find.byKey(const Key('markey_source_field'));
    final field = tester.widget<TextField>(fieldFinder);
    field.controller!.selection =
        const TextSelection.collapsed(offset: 15); // after "# Title\n\nsome b"
    await tester.pump();

    c.toggleMode(); // back to WYSIWYG
    await tester.pump();

    final sel = c.selection!;
    expect(sel.isCollapsed, isTrue);
    expect(sel.extent.nodeId, c.document.nodes.last.id); // body block
    expect((sel.extent.nodePosition as TextNodePosition).offset, 6); // "some b|"
    await tester.pumpWidget(const SizedBox());
  });
}
