# Keyboard shortcuts

On desktop and web (use <kbd>Cmd</kbd> on macOS, <kbd>Ctrl</kbd> elsewhere):

| Shortcut | Action |
|----------|--------|
| <kbd>Ctrl/Cmd</kbd>+<kbd>B</kbd> | Toggle **bold** on the selection |
| <kbd>Ctrl/Cmd</kbd>+<kbd>I</kbd> | Toggle *italic* on the selection |
| <kbd>Ctrl/Cmd</kbd>+<kbd>Z</kbd> | Undo |
| <kbd>Ctrl/Cmd</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd> | Redo |
| <kbd>←</kbd> / <kbd>→</kbd> | Move the caret (grapheme-aware, across blocks) |
| <kbd>Esc</kbd> | Dismiss the [slash menu](slash-menu.md) |

On mobile, the soft keyboard / IME drives input; selection uses touch gestures.

## Block reordering

| Shortcut | Action |
|----------|--------|
| <kbd>Alt</kbd>+<kbd>↑</kbd> / <kbd>Alt</kbd>+<kbd>↓</kbd> | Move the current block up / down |

Also available programmatically: `controller.moveBlockUp(nodeId)` / `moveBlockDown(nodeId)`.

## Paste

| Shortcut | Action |
|----------|--------|
| <kbd>Ctrl/Cmd</kbd>+<kbd>V</kbd> | Smart-paste: parse clipboard Markdown into formatted blocks |

Also `controller.pasteMarkdown(text)`.
