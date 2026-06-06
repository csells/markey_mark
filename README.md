# markey_mark

A from-scratch, **fully native, cross-platform WYSIWYG Markdown editor** for Flutter —
Google-Docs feel, **Markdown as the source of truth**, and a fluid switch between rich
(WYSIWYG) and raw (source) modes. **No WebView, no JavaScript — 100% native Flutter**, so it
runs on iOS, Android, web, Windows, macOS, and Linux from one codebase.

> Status: early. The core engine and a working vertical slice (paragraphs, headings,
> bold/italic/strike/code/links, live Markdown input rules, undo/redo, and the WYSIWYG⇄source
> toggle) are implemented and tested. See [`specs/design/`](specs/design/) for the full
> design and [`specs/design/roadmap.md`](specs/design/roadmap.md) for what's next.

## Why

The best web Markdown editors (ProseMirror/Milkdown, Lexical) can't run natively on all six
Flutter platforms — embedding them needs a WebView, which isn't first-party on Linux/Windows
and breaks on Flutter web. So `markey_mark` is built natively: it reuses Flutter's text
*painting* engine and replaces the single-run text *editing* widgets with its own document
model, command pipeline, and IME client — the approach proven by `super_editor` and
`appflowy_editor`, but with **Markdown as the canonical document** and an owned, configurable
serializer.

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:markey_mark/markey_mark.dart';

class MyEditor extends StatefulWidget {
  const MyEditor({super.key});
  @override
  State<MyEditor> createState() => _MyEditorState();
}

class _MyEditorState extends State<MyEditor> {
  final controller = MarkdownEditorController(markdown: '# Hello\n\nStart typing…');

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MarkdownEditor(controller: controller);
}
```

Read or set the Markdown at any time:

```dart
final md = controller.markdown;     // serialize the document to Markdown
controller.markdown = '# New doc';  // parse Markdown into the document
controller.toggleMode();            // switch WYSIWYG ⇄ source
```

## Features (today)

- Markdown is the source of truth, with an idempotent, AST-stable round trip.
- Live input rules: `# `→heading, `**bold**`, `_italic_`, `~~strike~~`, `` `code` ``.
- Paragraphs and headings (H1–H6); bold/italic/strike/inline-code/links.
- Custom native text-input (IME) client with grapheme-aware caret movement.
- Undo/redo with inverse operations and typing coalescing.
- Formatting toolbar with live state and a WYSIWYG⇄source toggle.
- Cross-platform, no WebView/JS.

## Architecture

Layered: Markdown pipeline (parse + own serializer) → document model (block tree + per-block
`Delta` of styled runs) → editing (inverse-op transactions + undo) → layout/render (reuse
`TextPainter`, paint selection-beneath/caret-above) → input (custom `DeltaTextInputClient`,
`Shortcuts/Actions/Intent`, input rules) → widget. Full details in
[`specs/design/`](specs/design/).

## Development

```sh
flutter pub get
flutter analyze
flutter test --coverage   # 187 tests; ~100% of core logic, 97%+ overall
flutter run               # in example/
```

## License

See [LICENSE](LICENSE).
