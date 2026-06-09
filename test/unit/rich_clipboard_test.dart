import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// An in-memory [ClipboardBridge] so clipboard logic can be tested without the
/// OS clipboard / platform plugins.
class FakeClipboardBridge implements ClipboardBridge {
  ClipboardPayload? stored;
  @override
  Future<void> write(ClipboardPayload payload) async => stored = payload;
  @override
  Future<ClipboardPayload?> read() async => stored;
}

void main() {
  group('selectionMarkdown', () {
    test('single-block selection yields inline markdown (no block prefix)', () {
      final c = MarkdownEditorController(markdown: '# Title');
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 2),
        extent: DocumentPosition.text(id, 5),
      ));
      expect(c.selectionMarkdown(), 'tle');
      c.dispose();
    });

    test('preserves inline marks within a block', () {
      final c = MarkdownEditorController(markdown: 'a **bold** c');
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 2),
        extent: DocumentPosition.text(id, 6),
      ));
      expect(c.selectionMarkdown(), '**bold**');
      c.dispose();
    });

    test('cross-block selection serializes the spanned structure', () {
      final c = MarkdownEditorController(markdown: 'one\n\ntwo\n\nthree');
      final first = c.document.nodes.first.id;
      final last = c.document.nodes.last.id;
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(first, 1),
        extent: DocumentPosition.text(last, 2),
      ));
      expect(c.selectionMarkdown(), 'ne\n\ntwo\n\nth');
      c.dispose();
    });

    test('returns null for a collapsed selection', () {
      final c = MarkdownEditorController(markdown: 'hi');
      c.setSelection(
          DocumentSelection.collapsed(DocumentPosition.text(c.document.nodes.first.id, 1)));
      expect(c.selectionMarkdown(), isNull);
      c.dispose();
    });
  });

  group('copy / cut / paste', () {
    test('copy writes markdown, html and plain-text flavors', () async {
      final c = MarkdownEditorController(markdown: '# Title');
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 0),
        extent: DocumentPosition.text(id, 5),
      ));
      final bridge = FakeClipboardBridge();
      await c.copy(bridge: bridge);
      expect(bridge.stored!.markdown, 'Title');
      expect(bridge.stored!.plainText, 'Title');
      expect(bridge.stored!.html, contains('Title'));
      c.dispose();
    });

    test('cut copies then removes the selection', () async {
      final c = MarkdownEditorController(markdown: 'hello world');
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection(
        base: DocumentPosition.text(id, 0),
        extent: DocumentPosition.text(id, 6),
      ));
      final bridge = FakeClipboardBridge();
      await c.cut(bridge: bridge);
      expect(bridge.stored!.markdown, 'hello ');
      expect(c.markdown, 'world');
      c.dispose();
    });

    test('paste prefers the markdown flavor and parses it', () async {
      final c = MarkdownEditorController();
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(id, 0)));
      final bridge = FakeClipboardBridge()
        ..stored = const ClipboardPayload(
            markdown: '**bold**', plainText: 'bold');
      await c.paste(bridge: bridge);
      expect((c.document.nodes.first as TextBlockNode)
          .delta
          .isFormatted(0, 4, 'bold'), isTrue);
      c.dispose();
    });

    test('pastePlain inserts literally without interpreting Markdown', () async {
      final c = MarkdownEditorController();
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(id, 0)));
      final bridge = FakeClipboardBridge()
        ..stored = const ClipboardPayload(
            markdown: '**not bold**', plainText: '**not bold**');
      await c.pastePlain(bridge: bridge);
      final node = c.document.nodes.first as TextBlockNode;
      expect(node.delta.toPlainText(), '**not bold**');
      expect(node.delta.isFormatted(0, node.delta.length, 'bold'), isFalse);
      c.dispose();
    });

    test('paste falls back to plain text when no markdown flavor', () async {
      final c = MarkdownEditorController();
      final id = c.document.nodes.first.id;
      c.setSelection(DocumentSelection.collapsed(DocumentPosition.text(id, 0)));
      final bridge = FakeClipboardBridge()
        ..stored = const ClipboardPayload(plainText: 'plain text');
      await c.paste(bridge: bridge);
      expect((c.document.nodes.first as TextBlockNode).delta.toPlainText(),
          'plain text');
      c.dispose();
    });
  });
}
