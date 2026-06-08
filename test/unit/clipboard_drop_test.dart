import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Unit coverage for the clipboard payload + bridges and the drag-and-drop
/// model (pure value types and the always-available system bridge).
void main() {
  group('DroppedItem', () {
    test('text item', () {
      const item = DroppedItem.text('# hi');
      expect(item.kind, DropKind.text);
      expect(item.value, '# hi');
      expect(item.alt, isNull);
    });

    test('image item with alt', () {
      const item = DroppedItem.image('pic.png', alt: 'a cat');
      expect(item.kind, DropKind.image);
      expect(item.value, 'pic.png');
      expect(item.alt, 'a cat');
    });

    test('value equality + hashCode', () {
      expect(const DroppedItem.text('x'), const DroppedItem.text('x'));
      expect(const DroppedItem.text('x').hashCode,
          const DroppedItem.text('x').hashCode);
      expect(const DroppedItem.text('x'), isNot(const DroppedItem.text('y')));
      expect(const DroppedItem.image('p', alt: 'a'),
          isNot(const DroppedItem.image('p', alt: 'b')));
    });
  });

  group('ClipboardPayload', () {
    test('isEmpty when all flavors are null/empty', () {
      expect(const ClipboardPayload().isEmpty, isTrue);
      expect(const ClipboardPayload(markdown: '', html: '').isEmpty, isTrue);
      expect(const ClipboardPayload(markdown: 'x').isEmpty, isFalse);
      expect(const ClipboardPayload(html: '<b>').isEmpty, isFalse);
      expect(const ClipboardPayload(plainText: 'x').isEmpty, isFalse);
    });

    test('value equality + hashCode', () {
      const a = ClipboardPayload(markdown: 'm', html: 'h', plainText: 'p');
      const b = ClipboardPayload(markdown: 'm', html: 'h', plainText: 'p');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const ClipboardPayload(markdown: 'm')));
    });
  });

  group('SystemClipboardBridge', () {
    testWidgets('round-trips Markdown through the system clipboard',
        (tester) async {
      const bridge = SystemClipboardBridge();
      await bridge.write(const ClipboardPayload(markdown: '# Title'));
      final read = await bridge.read();
      expect(read, isNotNull);
      expect(read!.markdown, '# Title');
      expect(read.plainText, '# Title');
    });

    testWidgets('write falls back to plainText when no markdown',
        (tester) async {
      const bridge = SystemClipboardBridge();
      await bridge.write(const ClipboardPayload(plainText: 'plain only'));
      final read = await bridge.read();
      expect(read!.markdown, 'plain only');
    });
  });

  group('SuperClipboardBridge', () {
    testWidgets('degrades to the system clipboard with no platform clipboard',
        (tester) async {
      // In the test environment sc.SystemClipboard.instance is null, so the
      // super bridge delegates to the system bridge — exercising that path.
      const bridge = SuperClipboardBridge();
      await bridge.write(const ClipboardPayload(markdown: 'hello'));
      final read = await bridge.read();
      expect(read!.markdown, 'hello');
    });
  });
}
