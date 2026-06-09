import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/widget/internal/context_menu.dart';

void main() {
  group('buildContextMenuActions', () {
    List<ContextMenuButtonType> typesFor({
      required bool hasSelection,
      required bool readOnly,
    }) =>
        buildContextMenuActions(
          hasSelection: hasSelection,
          readOnly: readOnly,
          onDismiss: () {},
          onCopy: () {},
          onCut: () {},
          onPaste: () {},
          onSelectAll: () {},
        ).map((i) => i.type).toList();

    test('no selection, editable: paste + select all', () {
      expect(typesFor(hasSelection: false, readOnly: false),
          [ContextMenuButtonType.paste, ContextMenuButtonType.selectAll]);
    });

    test('selection, editable: copy, cut, paste, select all', () {
      expect(typesFor(hasSelection: true, readOnly: false), [
        ContextMenuButtonType.copy,
        ContextMenuButtonType.cut,
        ContextMenuButtonType.paste,
        ContextMenuButtonType.selectAll,
      ]);
    });

    test('selection, read-only: copy + select all (no cut/paste)', () {
      expect(typesFor(hasSelection: true, readOnly: true),
          [ContextMenuButtonType.copy, ContextMenuButtonType.selectAll]);
    });

    test('no selection, read-only: select all only', () {
      expect(typesFor(hasSelection: false, readOnly: true),
          [ContextMenuButtonType.selectAll]);
    });

    test('every item dismisses the menu before running its action', () {
      final calls = <String>[];
      final items = buildContextMenuActions(
        hasSelection: true,
        readOnly: false,
        onDismiss: () => calls.add('dismiss'),
        onCopy: () => calls.add('copy'),
        onCut: () => calls.add('cut'),
        onPaste: () => calls.add('paste'),
        onSelectAll: () => calls.add('selectAll'),
      );
      for (final item in items) {
        item.onPressed!();
      }
      expect(calls, [
        'dismiss', 'copy', //
        'dismiss', 'cut', //
        'dismiss', 'paste', //
        'dismiss', 'selectAll', //
      ]);
    });
  });

  group('BrowserContextMenuSuppression (ref counting)', () {
    setUp(BrowserContextMenuSuppression.resetForTest);

    test('acquire/release is balanced and never goes negative', () {
      expect(BrowserContextMenuSuppression.activeRefs, 0);
      BrowserContextMenuSuppression.acquire();
      BrowserContextMenuSuppression.acquire();
      expect(BrowserContextMenuSuppression.activeRefs, 2);
      BrowserContextMenuSuppression.release();
      expect(BrowserContextMenuSuppression.activeRefs, 1);
      // Two editors mounted, one disposed: still suppressed (the bug this fixes).
      BrowserContextMenuSuppression.release();
      expect(BrowserContextMenuSuppression.activeRefs, 0);
      BrowserContextMenuSuppression.release(); // underflow guard
      expect(BrowserContextMenuSuppression.activeRefs, 0);
    });
  });
}
