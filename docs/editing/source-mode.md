# Source mode

Toggle between the rich (WYSIWYG) view and the raw **Markdown source** at any time using the
toolbar's code button. Markdown is always the source of truth, so nothing is lost in either
direction.

![Source mode with syntax highlighting](../images/source-mode.png)

The source view is a real editor with **native Markdown syntax highlighting** (headings,
emphasis, code, links, list/quote markers) — no WebView or JavaScript.

```dart
controller.toggleMode();          // switch modes
controller.mode;                  // EditorMode.wysiwyg | EditorMode.source
controller.markdown;              // the current Markdown (either mode)
```
