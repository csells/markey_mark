import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Coverage for controller branches the behavioural suite doesn't exercise:
/// stats over table cells, word/line deletion over ranges and at block edges,
/// and TSV clipboard copy of a cell range.
void main() {
  DocumentPosition cell(String id, int r, int col) =>
      DocumentPosition(nodeId: id, nodePosition: TableCellPosition(r, col, 0));

  test('documentStats tallies table cells', () {
    final c = MarkdownEditorController(
        markdown: 'Hello world\n\n| a b | c |\n|---|---|\n| d | e |');
    addTearDown(c.dispose);
    final stats = c.documentStats();
    // "Hello world" (2) + cells: "a b"(2) c d e (1 each) = 2+2+1+1+1 = 7 words.
    expect(stats.words, 7);
    expect(stats.blocks, 2); // paragraph + table
    expect(stats.characters, greaterThan(0));
  });

  test('deleteByGranularity over a multi-block selection deletes the range', () {
    final c = MarkdownEditorController(markdown: 'one\n\ntwo');
    addTearDown(c.dispose);
    final a = c.document.nodes[0].id;
    final b = c.document.nodes[1].id;
    c.setSelection(DocumentSelection(
      base: DocumentPosition.text(a, 1),
      extent: DocumentPosition.text(b, 2),
    ));
    c.deleteByGranularity(forward: false, granularity: CaretGranularity.word);
    expect(c.markdown, 'oo'); // "o" + "o" of the surviving ends, merged
  });

  test('deleteByGranularity backward at block start merges with previous', () {
    final c = MarkdownEditorController(markdown: 'one\n\ntwo');
    addTearDown(c.dispose);
    final b = c.document.nodes[1].id;
    c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(b, 0)));
    c.deleteByGranularity(forward: false, granularity: CaretGranularity.word);
    expect(c.document.length, 1); // blocks merged
    expect(c.markdown, 'onetwo');
  });

  testWidgets('copying a cell-range selection writes TSV to the clipboard',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    String? stored;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        stored = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final c = MarkdownEditorController(
        markdown: '| a | b |\n|---|---|\n| c | d |');
    addTearDown(c.dispose);
    final id = c.document.nodes.first.id;
    c.setSelection(
        DocumentSelection(base: cell(id, 0, 0), extent: cell(id, 1, 1)));
    await c.copy();
    expect(stored, 'a\tb\nc\td');
  });
}
