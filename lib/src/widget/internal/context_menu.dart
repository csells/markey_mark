import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;

/// Builds the editor's right-click / long-press menu items for the current
/// [hasSelection] / [readOnly] state. Each item dismisses the menu before
/// running its action, so call sites don't repeat that pairing.
///
/// Pure and dependency-free so it can be unit-tested without pumping a widget.
List<ContextMenuButtonItem> buildContextMenuActions({
  required bool hasSelection,
  required bool readOnly,
  required VoidCallback onDismiss,
  required VoidCallback onCopy,
  required VoidCallback onCut,
  required VoidCallback onPaste,
  required VoidCallback onSelectAll,
}) {
  ContextMenuButtonItem item(ContextMenuButtonType type, VoidCallback action) =>
      ContextMenuButtonItem(
        type: type,
        onPressed: () {
          onDismiss();
          action();
        },
      );
  return [
    if (hasSelection) item(ContextMenuButtonType.copy, onCopy),
    if (hasSelection && !readOnly) item(ContextMenuButtonType.cut, onCut),
    if (!readOnly) item(ContextMenuButtonType.paste, onPaste),
    item(ContextMenuButtonType.selectAll, onSelectAll),
  ];
}

/// Ref-counted suppression of the browser's native right-click menu on web, so
/// the editor's own context menu shows instead of Chrome's.
///
/// Ref-counted because `BrowserContextMenu` is a single global toggle: if two
/// editors are mounted and one is disposed, a naive enable() would re-show the
/// browser menu under the editor that's still up. Suppression lifts only when
/// the last editor releases.
abstract final class BrowserContextMenuSuppression {
  static int _refs = 0;

  /// Number of live holders (an editor acquires on mount, releases on dispose).
  static int get activeRefs => _refs;

  /// Acquire suppression; disables the browser menu on the 0 -> 1 transition.
  /// Fire-and-forget: we don't await the toggle and `.ignore()` its Future so
  /// its errors aren't surfaced (the channel isn't wired up under flutter_test).
  static void acquire() {
    if (_refs++ == 0 && kIsWeb) BrowserContextMenu.disableContextMenu().ignore();
  }

  /// Release suppression; restores the browser menu on the 1 -> 0 transition.
  /// Releasing at zero is a no-op (the count never goes negative).
  static void release() {
    if (_refs > 0 && --_refs == 0 && kIsWeb) BrowserContextMenu.enableContextMenu().ignore();
  }

  @visibleForTesting
  static void resetForTest() => _refs = 0;
}
