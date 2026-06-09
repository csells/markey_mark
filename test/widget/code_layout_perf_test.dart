import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';
import 'package:markey_mark/src/render/code_layout.dart';

/// Strict intra-block latency gate (the documented "remaining perf frontier").
///
/// A single pathologically large block — realistically a pasted code block of
/// hundreds/thousands of lines — must NOT re-shape its entire `TextPainter` on
/// every keystroke. Like CodeMirror's viewport line rendering, layout is
/// per-line and cached, so editing one line re-shapes only that line (O(changed
/// line)), not O(block size). `CodeLayout.debugShapedChars` counts characters
/// actually run through `TextPainter.layout` — a deterministic, timing-free
/// gate.
void main() {
  Future<(MarkdownEditorController, DeltaTextInputClient)> pump(
    WidgetTester tester,
    MarkdownEditorController c,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 500,
            child: MarkdownEditor(controller: c, enableDrop: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(MarkdownEditor));
    await tester.pump();
    final client =
        tester.state(find.byType(MarkdownEditor)) as DeltaTextInputClient;
    return (c, client);
  }

  // A big code block: `lines` lines of source, joined by newlines, in one
  // fenced block (so it is a single CodeBlockNode in the document).
  String bigCodeDoc(int lines) {
    final code =
        List.generate(lines, (i) => 'const value$i = compute($i) + offset;')
            .join('\n');
    return '```dart\n$code\n```';
  }

  testWidgets('editing a giant code block re-shapes O(one line), not O(block)',
      (tester) async {
    const lines = 1500;
    final c = MarkdownEditorController(markdown: bigCodeDoc(lines));
    addTearDown(c.dispose);
    final (_, client) = await pump(tester, c);

    final node = c.document.nodes.first as CodeBlockNode;
    expect(node, isA<CodeBlockNode>());
    final code = node.code;
    final totalLen = code.length;
    // The first line is "const value0 = compute(0) + offset;".
    final firstLineEnd = code.indexOf('\n');
    // Place the caret inside the first line and type one character there.
    c.placeCaretAt(DocumentPosition.text(node.id, 5));
    await tester.pump();

    // Measure exactly the shaping done by ONE keystroke (after the initial
    // full layout has already happened and been cached).
    CodeLayout.debugShapedChars = 0;
    client.updateEditingValueWithDeltas([
      TextEditingDeltaInsertion(
        oldText: code,
        textInserted: 'Z',
        insertionOffset: 5,
        selection: const TextSelection.collapsed(offset: 6),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();

    // Only the edited line re-shapes. Allow generous headroom (a handful of
    // lines) for incidental relayout, but it must be a tiny fraction of the
    // whole block — a monolithic re-shape would be ~`totalLen` characters.
    expect(CodeLayout.debugShapedChars, greaterThan(0),
        reason: 'the edited line must actually re-shape');
    expect(CodeLayout.debugShapedChars, lessThan(firstLineEnd * 6),
        reason: 're-shaping must be O(changed line), not O(block) '
            '(total block is $totalLen chars)');
    expect(CodeLayout.debugShapedChars, lessThan(totalLen ~/ 10),
        reason: 'a keystroke must not re-shape a large fraction of the block');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('per-keystroke code shaping is independent of block size',
      (tester) async {
    Future<int> shapeCharsForOneKeystroke(int lines) async {
      final c = MarkdownEditorController(markdown: bigCodeDoc(lines));
      addTearDown(c.dispose);
      final (_, client) = await pump(tester, c);
      final node = c.document.nodes.first as CodeBlockNode;
      final code = node.code;
      c.placeCaretAt(DocumentPosition.text(node.id, 3));
      await tester.pump();
      CodeLayout.debugShapedChars = 0;
      client.updateEditingValueWithDeltas([
        TextEditingDeltaInsertion(
          oldText: code,
          textInserted: 'q',
          insertionOffset: 3,
          selection: const TextSelection.collapsed(offset: 4),
          composing: TextRange.empty,
        ),
      ]);
      await tester.pump();
      final shaped = CodeLayout.debugShapedChars;
      await tester.pumpWidget(const SizedBox());
      return shaped;
    }

    final small = await shapeCharsForOneKeystroke(100);
    final huge = await shapeCharsForOneKeystroke(3000);
    // 30x the block size must not increase per-keystroke shaping: only the
    // changed line re-shapes either way.
    expect(huge, lessThan(small * 3 + 200),
        reason: 'small=$small chars, huge=$huge chars — '
            'per-keystroke shaping must be ~constant in block size');
  });

  testWidgets('editing a giant code block re-tokenizes O(changed line), not O(block)',
      (tester) async {
    const lines = 2000;
    final c = MarkdownEditorController(markdown: bigCodeDoc(lines));
    addTearDown(c.dispose);
    final (_, client) = await pump(tester, c);

    final node = c.document.nodes.first as CodeBlockNode;
    final code = node.code;
    final firstLineEnd = code.indexOf('\n');
    c.placeCaretAt(DocumentPosition.text(node.id, 4));
    await tester.pump();

    // Measure the highlight tokenizing done by ONE keystroke. Editing a line
    // whose end-state (e.g. not inside a block comment) is unchanged must only
    // re-tokenize that line — the rest hit the (startState, text) cache.
    CodeLayout.debugTokenizedChars = 0;
    client.updateEditingValueWithDeltas([
      TextEditingDeltaInsertion(
        oldText: code,
        textInserted: 'k',
        insertionOffset: 4,
        selection: const TextSelection.collapsed(offset: 5),
        composing: TextRange.empty,
      ),
    ]);
    await tester.pump();

    expect(CodeLayout.debugTokenizedChars, greaterThan(0),
        reason: 'the edited line must re-tokenize');
    expect(CodeLayout.debugTokenizedChars, lessThan(firstLineEnd * 6),
        reason: 're-tokenizing must be O(changed line), not O(block) '
            '(block is ${code.length} chars)');
    await tester.pumpWidget(const SizedBox());
  });
}

