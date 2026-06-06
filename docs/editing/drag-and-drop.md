# Drag & drop

The editor accepts OS drag-and-drop of text and images, powered by the native
`super_drag_and_drop` plugin (no WebView, no JavaScript).

- **Drop text** (from another app or a selection) — it's smart-pasted as
  Markdown at the drop point.
- **Drop an image file/URL** — it becomes an image block on its own line,
  without overwriting nearby text.

Multiple dropped items are inserted in order.

## Enabling / disabling

Drop is on by default. Read-only editors never accept drops. To turn it off
(for example in tests that render with `WidgetTester.runAsync`, where the native
plugin isn't available):

```dart
MarkdownEditor(controller: controller, enableDrop: false)
```

## Programmatic API

The drop handling is built on a testable seam — call it directly to simulate or
script drops:

```dart
controller.applyDrop(
  const [
    DroppedItem.text('# Pasted heading'),
    DroppedItem.image('https://example.com/pic.png', alt: 'a pic'),
  ],
  at: somePosition, // optional caret target
);
```

## Block reordering

Reordering existing blocks doesn't need OS drag-and-drop — use
<kbd>Alt</kbd>+<kbd>↑</kbd>/<kbd>↓</kbd> or `controller.moveBlockUp/Down`
(see [keyboard shortcuts](keyboard-shortcuts.md#block-reordering)).
