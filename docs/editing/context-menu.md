# Context menu

Right-click (or long-press on touch) anywhere in the editor to open a native
context menu — Flutter's `AdaptiveTextSelectionToolbar`, so it matches each
platform's look and feel. No WebView, no JavaScript.

The menu shows only the actions that apply:

| Action | When it appears |
| --- | --- |
| **Copy** | a non-empty selection exists |
| **Cut** | a non-empty selection exists and the editor is editable |
| **Paste** | the editor is editable |
| **Select all** | always |

Each action routes through the same [clipboard](clipboard.md) and selection
APIs as the keyboard shortcuts, so behavior is identical however you invoke it.
Read-only editors offer only **Copy** and **Select all**.
