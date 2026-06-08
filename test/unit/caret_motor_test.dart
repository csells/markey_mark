import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// The pure (layout-independent) caret/selection motor. It computes the next
/// caret position for a granularity (character/word/line/document) in either
/// direction, crossing block boundaries and working uniformly across
/// paragraphs, code blocks, and table cells — the logic Flutter's
/// `RenderEditable` provides for a single field, generalized to our multi-block
/// document. Vertical (up/down) movement needs paint geometry and is tested at
/// the widget layer; everything here is pure and exhaustively unit-tested.
void main() {
  DocumentPosition tp(String id, int o) => DocumentPosition.text(id, o);
  int off(DocumentPosition? p) => (p!.nodePosition as TextNodePosition).offset;

  group('character movement', () {
    final doc = Document([
      TextBlockNode.paragraph(id: 'a', delta: Delta.text('hello')),
      TextBlockNode.paragraph(id: 'b', delta: Delta.text('world')),
    ]);
    final motor = CaretMotor(doc);

    test('moves right one grapheme within a block', () {
      final r = motor.move(tp('a', 1),
          forward: true, granularity: CaretGranularity.character);
      expect(r!.nodeId, 'a');
      expect(off(r), 2);
    });

    test('moves left one grapheme within a block', () {
      final r = motor.move(tp('a', 3),
          forward: false, granularity: CaretGranularity.character);
      expect(off(r), 2);
    });

    test('crossing the end of a block lands at the start of the next', () {
      final r = motor.move(tp('a', 5),
          forward: true, granularity: CaretGranularity.character);
      expect(r!.nodeId, 'b');
      expect(off(r), 0);
    });

    test('crossing the start of a block lands at the end of the previous', () {
      final r = motor.move(tp('b', 0),
          forward: false, granularity: CaretGranularity.character);
      expect(r!.nodeId, 'a');
      expect(off(r), 5);
    });

    test('right at the very end of the document returns null', () {
      final r = motor.move(tp('b', 5),
          forward: true, granularity: CaretGranularity.character);
      expect(r, isNull);
    });

    test('left at the very start of the document returns null', () {
      final r = motor.move(tp('a', 0),
          forward: false, granularity: CaretGranularity.character);
      expect(r, isNull);
    });
  });

  test('grapheme movement treats an emoji cluster as one step', () {
    final doc = Document([
      TextBlockNode.paragraph(id: 'a', delta: Delta.text('a👨‍👩‍👧b')),
    ]);
    final motor = CaretMotor(doc);
    final r = motor.move(tp('a', 1),
        forward: true, granularity: CaretGranularity.character);
    // The whole ZWJ family sequence is a single grapheme: skip all of it.
    expect(off(r), 1 + '👨‍👩‍👧'.length);
  });

  group('word movement', () {
    final doc = Document([
      TextBlockNode.paragraph(id: 'a', delta: Delta.text('foo bar.baz qux')),
    ]);
    final motor = CaretMotor(doc);

    test('word-right stops at the end of the current word', () {
      final r = motor.move(tp('a', 0),
          forward: true, granularity: CaretGranularity.word);
      expect(off(r), 3); // end of "foo"
    });

    test('word-right from a space skips to the end of the next word', () {
      final r = motor.move(tp('a', 3),
          forward: true, granularity: CaretGranularity.word);
      expect(off(r), 7); // "bar"
    });

    test('word-right treats punctuation as its own boundary', () {
      final r = motor.move(tp('a', 7),
          forward: true, granularity: CaretGranularity.word);
      expect(off(r), 8); // the "." between bar and baz
    });

    test('word-left stops at the start of the current word', () {
      final r = motor.move(tp('a', 6),
          forward: false, granularity: CaretGranularity.word);
      expect(off(r), 4); // start of "bar"
    });
  });

  group('line boundary (logical)', () {
    test('paragraph: start/end span the whole block', () {
      final doc = Document([
        TextBlockNode.paragraph(id: 'a', delta: Delta.text('a sentence here')),
      ]);
      final motor = CaretMotor(doc);
      expect(
          off(motor.move(tp('a', 6),
              forward: false, granularity: CaretGranularity.lineBoundary)),
          0);
      expect(
          off(motor.move(tp('a', 6),
              forward: true, granularity: CaretGranularity.lineBoundary)),
          15);
    });

    test('code block: start/end span only the physical line', () {
      final doc = Document([
        CodeBlockNode(id: 'c', code: 'line one\nline two\nthree'),
      ]);
      final motor = CaretMotor(doc);
      // Offset 11 is inside "line two" (chars 9..17).
      expect(
          off(motor.move(tp('c', 11),
              forward: false, granularity: CaretGranularity.lineBoundary)),
          9);
      expect(
          off(motor.move(tp('c', 11),
              forward: true, granularity: CaretGranularity.lineBoundary)),
          17);
    });
  });

  test('character movement works inside a code block and over its newlines', () {
    final doc = Document([CodeBlockNode(id: 'c', code: 'ab\ncd')]);
    final motor = CaretMotor(doc);
    // From end of first physical line, right moves onto the newline char.
    final r = motor.move(tp('c', 2),
        forward: true, granularity: CaretGranularity.character);
    expect(r!.nodeId, 'c');
    expect(off(r), 3);
  });

  group('document boundary', () {
    final doc = Document([
      TextBlockNode.paragraph(id: 'a', delta: Delta.text('first')),
      CodeBlockNode(id: 'c', code: 'x\ny'),
      TextBlockNode.paragraph(id: 'b', delta: Delta.text('last')),
    ]);
    final motor = CaretMotor(doc);

    test('start goes to offset 0 of the first editable block', () {
      final r = motor.move(tp('c', 2),
          forward: false, granularity: CaretGranularity.documentBoundary);
      expect(r!.nodeId, 'a');
      expect(off(r), 0);
    });

    test('end goes to the end of the last editable block', () {
      final r = motor.move(tp('c', 0),
          forward: true, granularity: CaretGranularity.documentBoundary);
      expect(r!.nodeId, 'b');
      expect(off(r), 4);
    });
  });

  test('crossing skips atomic (non-text) blocks', () {
    final doc = Document([
      TextBlockNode.paragraph(id: 'a', delta: Delta.text('x')),
      ImageNode(id: 'img', url: 'pic.png'),
      TextBlockNode.paragraph(id: 'b', delta: Delta.text('y')),
    ]);
    final motor = CaretMotor(doc);
    final r = motor.move(tp('a', 1),
        forward: true, granularity: CaretGranularity.character);
    expect(r!.nodeId, 'b'); // image skipped
    expect(off(r), 0);
  });

  group('table cell movement stays within the cell', () {
    final doc = Document([
      TableNode(
        rows: [
          [Delta.text('h1'), Delta.text('h2')],
          [Delta.text('cell'), Delta.text('other')],
        ],
        alignments: const [TableAlign.none, TableAlign.none],
        id: 't',
      ),
    ]);
    final motor = CaretMotor(doc);

    DocumentPosition cellPos(int r, int c, int o) =>
        DocumentPosition(nodeId: 't', nodePosition: TableCellPosition(r, c, o));

    test('character right moves within the cell', () {
      final r = motor.move(cellPos(1, 0, 1),
          forward: true, granularity: CaretGranularity.character);
      final p = r!.nodePosition as TableCellPosition;
      expect([p.row, p.col, p.offset], [1, 0, 2]);
    });

    test('character right at cell end does not leave the cell', () {
      final r = motor.move(cellPos(1, 0, 4),
          forward: true, granularity: CaretGranularity.character);
      expect(r, isNull); // no movement out of the cell
    });

    test('line end goes to the end of the cell text', () {
      final r = motor.move(cellPos(1, 1, 1),
          forward: true, granularity: CaretGranularity.lineBoundary);
      final p = r!.nodePosition as TableCellPosition;
      expect(p.offset, 5); // "other"
    });
  });

  group('selection ranges (double/triple click)', () {
    final doc = Document([
      TextBlockNode.paragraph(id: 'a', delta: Delta.text('foo bar baz')),
    ]);
    final motor = CaretMotor(doc);

    test('wordRangeAt selects the word under the offset', () {
      final r = motor.wordRangeAt(tp('a', 5))!; // inside "bar"
      expect(off(r.$1), 4);
      expect(off(r.$2), 7);
    });

    test('lineRangeAt selects the whole logical line', () {
      final r = motor.lineRangeAt(tp('a', 5))!;
      expect(off(r.$1), 0);
      expect(off(r.$2), 11);
    });

    test('wordRangeAt just after a word still selects that word', () {
      final r = motor.wordRangeAt(tp('a', 3))!; // the space after "foo"
      expect(off(r.$1), 0);
      expect(off(r.$2), 3);
    });

    test('lineRangeAt on a code block selects only the physical line', () {
      final cdoc = Document([CodeBlockNode(id: 'c', code: 'one\ntwo\nthree')]);
      final r = CaretMotor(cdoc).lineRangeAt(tp('c', 5))!; // inside "two"
      expect(off(r.$1), 4);
      expect(off(r.$2), 7);
    });

    test('ranges are null off a text-bearing block', () {
      final idoc = Document([ImageNode(id: 'img', url: 'p.png')]);
      expect(CaretMotor(idoc).wordRangeAt(tp('img', 0)), isNull);
      expect(CaretMotor(idoc).lineRangeAt(tp('img', 0)), isNull);
    });
  });
}
