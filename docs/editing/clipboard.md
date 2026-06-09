# Clipboard (copy / cut / paste)

markey_mark supports multi-flavor copy/cut/paste with Markdown as the source of
truth.

| Shortcut | Action |
| --- | --- |
| <kbd>Ctrl/Cmd</kbd>+<kbd>C</kbd> | Copy the selection |
| <kbd>Ctrl/Cmd</kbd>+<kbd>X</kbd> | Cut the selection |
| <kbd>Ctrl/Cmd</kbd>+<kbd>V</kbd> | Smart-paste (parses Markdown structure) |
| <kbd>Ctrl/Cmd</kbd>+<kbd>Shift</kbd>+<kbd>V</kbd> | Paste as plain text (no Markdown parsing) |

Copy/cut place three flavors on the clipboard:

- **Markdown** — the canonical form (inline Markdown for a within-block
  selection; full block structure for a cross-block selection).
- **HTML** — so pasting into rich targets (mail, docs) keeps formatting.
- **Plain text** — for plain targets.

Paste prefers the Markdown flavor and parses it into formatted blocks, falling
back to plain text. It replaces the current selection (including
[cross-block](keyboard-shortcuts.md#cross-block-selection) ones).

**Paste as plain text** (<kbd>Ctrl/Cmd</kbd>+<kbd>Shift</kbd>+<kbd>V</kbd>, or
`controller.pastePlain()`) inserts the clipboard text *literally* — no Markdown
interpretation and no input rules — so `**x**` stays as the five characters
`**x**`.

## Choosing a clipboard backend

By default the editor uses `SystemClipboardBridge` (Flutter's built-in
plain-text clipboard) — zero extra setup, works everywhere. For true
multi-flavor OS clipboard interchange, pass the native, no-JavaScript
`super_clipboard`-backed bridge:

```dart
MarkdownEditor(
  controller: controller,
  clipboard: const SuperClipboardBridge(),
)
```

The `ClipboardBridge` interface is a seam: implement your own to integrate any
clipboard source. Programmatic API: `controller.copy()`, `controller.cut()`,
`controller.paste()`, and `controller.selectionMarkdown()`.
