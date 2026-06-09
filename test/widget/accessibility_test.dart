import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

void main() {
  Future<MarkdownEditorController> pump(
      WidgetTester tester, String markdown,
      {bool readOnly = false}) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: MarkdownEditor(
                controller: c, enableDrop: false, readOnly: readOnly),
          ),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  testWidgets('headings expose header semantics with their text',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, '# Big Title\n\nBody text here.');

    expect(find.bySemanticsLabel('Big Title'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Big Title'));
    expect(node.flagsCollection.isHeader, isTrue);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paragraphs expose their text as a semantics label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, 'A plain paragraph.');
    expect(find.bySemanticsLabel('A plain paragraph.'), findsOneWidget);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('images expose their alt text as an image semantics label',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, '![A friendly cat](https://example.com/cat.png)');
    final node = tester.getSemantics(find.bySemanticsLabel('A friendly cat'));
    expect(node.flagsCollection.isImage, isTrue);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  group('editable text-field semantics (reuse SemanticsConfiguration)', () {
    // The text-field node is a descendant of the editor; find it by flag.
    SemanticsNode textField(WidgetTester tester) {
      final root = tester.getSemantics(find.byType(MarkdownEditor));
      SemanticsNode? found;
      void visit(SemanticsNode n) {
        if (n.getSemanticsData().flagsCollection.isTextField) {
          found ??= n;
          return;
        }
        n.visitChildren((c) {
          if (found == null) visit(c);
          return true;
        });
      }

      visit(root);
      return found!;
    }

    testWidgets('the editor exposes an editable text field with its value',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, 'hello world');
      expect(
        textField(tester),
        isSemantics(
          isTextField: true,
          isReadOnly: false,
          value: 'hello world',
          hasMoveCursorForwardByCharacterAction: true,
          hasMoveCursorBackwardByCharacterAction: true,
          hasSetSelectionAction: true,
        ),
      );
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a read-only editor reports read-only text-field semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, 'frozen', readOnly: true);
      expect(
        textField(tester),
        isSemantics(isTextField: true, isReadOnly: true),
      );
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the move-cursor semantic action moves the document caret',
        (tester) async {
      final handle = tester.ensureSemantics();
      final c = await pump(tester, 'abc');
      final id = c.document.nodes.first.id;
      c.placeCaretAt(DocumentPosition.text(id, 0));
      await tester.pump();

      final owner = textField(tester).owner!;
      owner.performAction(textField(tester).id,
          SemanticsAction.moveCursorForwardByCharacter, true);
      await tester.pump();

      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 1);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('exposes the live caret as textSelection + word actions',
        (tester) async {
      final handle = tester.ensureSemantics();
      final c = await pump(tester, 'one two three');
      final id = c.document.nodes.first.id;
      c.placeCaretAt(DocumentPosition.text(id, 3));
      await tester.pump();

      expect(
        textField(tester),
        isSemantics(
          isTextField: true,
          hasMoveCursorForwardByWordAction: true,
          hasMoveCursorBackwardByWordAction: true,
        ),
      );
      // The live caret is exposed as the semantic text selection.
      expect(textField(tester).getSemanticsData().textSelection,
          const TextSelection.collapsed(offset: 3));

      // The word semantic action moves the caret by a word.
      final owner = textField(tester).owner!;
      owner.performAction(textField(tester).id,
          SemanticsAction.moveCursorForwardByWord, false);
      await tester.pump();
      expect((c.selection!.extent.nodePosition as TextNodePosition).offset, 7);
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
