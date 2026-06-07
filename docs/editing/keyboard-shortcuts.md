# Keyboard shortcuts

On desktop and web (use <kbd>Cmd</kbd> on macOS, <kbd>Ctrl</kbd> elsewhere):

| Shortcut | Action |
|----------|--------|
| <kbd>Ctrl/Cmd</kbd>+<kbd>B</kbd> | Toggle **bold** on the selection |
| <kbd>Ctrl/Cmd</kbd>+<kbd>I</kbd> | Toggle *italic* on the selection |
| <kbd>Ctrl/Cmd</kbd>+<kbd>Z</kbd> | Undo |
| <kbd>Ctrl/Cmd</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd> | Redo |
| <kbd>Ctrl/Cmd</kbd>+<kbd>A</kbd> | Select the whole document |
| <kbd>←</kbd> / <kbd>→</kbd> | Move the caret (grapheme-aware, across blocks) |
| <kbd>Shift</kbd>+click | Extend the selection to the click (across blocks) |
| <kbd>Esc</kbd> | Dismiss the [slash menu](slash-menu.md) |

On mobile, the soft keyboard / IME drives input; selection uses touch gestures.

## Cross-block selection

A selection can span multiple blocks. Create one by **dragging with the mouse**
(or stylus) across blocks, with <kbd>Ctrl/Cmd</kbd>+<kbd>A</kbd> (whole document),
or with <kbd>Shift</kbd>+click (from the caret to where you click — even in
another block). A mouse drag freezes the scroll view for the duration so it
selects rather than scrolls; touch drags still scroll. Then:

- **Type** to replace the entire selection with the typed text.
- **Backspace** / **Delete** to remove it, merging the surviving ends of the
  first and last blocks into one (which keeps the first block's type).
- **Bold/italic/…** (toolbar or shortcut) to format every spanned block at once.

The whole operation is a single undo step. Programmatically: `controller.selectAll()`.

## Block reordering

| Action | How |
|--------|-----|
| Move the current block up / down | <kbd>Alt</kbd>+<kbd>↑</kbd> / <kbd>Alt</kbd>+<kbd>↓</kbd> |
| Move a block anywhere | Drag its **handle** (the grip that appears in the left gutter on hover) onto another block |

Also available programmatically: `controller.moveBlockUp(nodeId)` /
`moveBlockDown(nodeId)`, and `controller.reorderBlock(fromIndex, toIndex)`.

## Paste

| Shortcut | Action |
|----------|--------|
| <kbd>Ctrl/Cmd</kbd>+<kbd>V</kbd> | Smart-paste: parse clipboard Markdown into formatted blocks |

Also `controller.pasteMarkdown(text)`.
