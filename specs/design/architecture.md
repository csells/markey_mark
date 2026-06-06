# 02 — Architecture

## 02.1 The layered architecture

The editor is organized as a stack of layers, each depending only on those below it. This
mirrors the separation that both `super_editor` (Document / Composer / Editor / Layout) and
`appflowy_editor` (Document / EditorState / Services) converged on, adapted so **Markdown is
the canonical form**.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ L7  Public API:  MarkdownEditor widget · MarkdownEditorController · themes │
├──────────────────────────────────────────────────────────────────────────┤
│ L6  Chrome & UX:  toolbar · bubble toolbar · slash menu · block handles ·  │
│                   context menus · source-mode view · placeholder           │
├──────────────────────────────────────────────────────────────────────────┤
│ L5  Input:  DeltaTextInputClient (IME) · Shortcuts/Actions/Intents ·       │
│             gesture recognizers · input rules · clipboard · drag & drop    │
├──────────────────────────────────────────────────────────────────────────┤
│ L4  Editing:  Editor · EditRequest → EditCommand → EditEvent → reactions · │
│               Transaction/Operation · UndoManager                          │
├──────────────────────────────────────────────────────────────────────────┤
│ L3  Layout & geometry:  DocumentLayout · BlockComponent registry ·         │
│             Offset↔DocumentPosition · caret/selection Rects (cross-block)  │
├──────────────────────────────────────────────────────────────────────────┤
│ L2  Rendering primitives:  TextPainter / Paragraph / RenderParagraph /     │
│             InlineSpan + WidgetSpan  (reused from Flutter)                  │
├──────────────────────────────────────────────────────────────────────────┤
│ L1  Document model:  Document · Node tree · Delta (attributed inline text)·│
│             DocumentSelection / DocumentPosition / NodePosition            │
├──────────────────────────────────────────────────────────────────────────┤
│ L0  Markdown pipeline:  parser (dart-lang/markdown + custom syntaxes) ·    │
│             AST→model mapping · model→Markdown serializer · source hints    │
└──────────────────────────────────────────────────────────────────────────┘
```

**Data-flow summary (a keystroke's life):**

1. The platform IME delivers a `TextEditingDelta` to our `DeltaTextInputClient` (L5).
2. Input-rule matching (L5) inspects the delta against the active block's text; a match
   produces an `EditRequest`. Otherwise the raw insertion produces an `EditRequest`.
3. The `Editor` (L4) turns the request into `EditCommand`(s), applies them as a
   `Transaction` of `Operation`s mutating the `Document` (L1), records inverse ops for undo,
   and emits `EditEvent`s. Reactions (e.g. table normalization) may append more commands.
4. The document notifies; affected `BlockComponent`s (L3) rebuild, re-shaping text via
   `TextPainter` (L2) and re-reporting caret/selection geometry.
5. The IME client re-serializes the (possibly changed) active region back to the platform so
   the OS keyboard stays in sync.
6. At any time, the model can be serialized to Markdown (L0) — for the source view, copy, or
   `controller.markdown`.

## 02.2 Module / package structure

The published package is **pure Dart/Flutter** (no platform channels of our own; native
needs are delegated to `super_clipboard`/`super_drag_and_drop`). Internally it is organized
into clear modules under `lib/src/`, with a curated public surface in `lib/`.

```
markey_mark/
├── pubspec.yaml
├── lib/
│   ├── markey_mark.dart            # public barrel: exports the supported API only
│   └── src/
│       ├── model/                  # L1: document model
│       │   ├── document.dart       #   Document, MutableDocument
│       │   ├── node.dart           #   Node, BlockNode, TextBlockNode, leaf/atomic nodes
│       │   ├── delta.dart          #   Delta, TextOp, Attribute, AttributedText helpers
│       │   ├── position.dart       #   DocumentPosition, NodePosition, TextNodePosition
│       │   ├── selection.dart      #   DocumentSelection, affinity
│       │   └── nodes/              #   concrete node types (paragraph, heading, list, ...)
│       ├── markdown/               # L0: markdown pipeline
│       │   ├── parser.dart         #   Document text -> dart-lang/markdown AST (+ custom)
│       │   ├── ast_mapper.dart     #   AST -> model (block registry + inline visitor)
│       │   ├── serializer.dart     #   model -> markdown (per-node + per-attribute rules)
│       │   ├── source_hints.dart   #   optional fidelity hints (marker char, fence, ...)
│       │   └── syntaxes/           #   custom math/mermaid/etc. block & inline syntaxes
│       ├── editing/                # L4: command pipeline
│       │   ├── editor.dart         #   Editor, CommandExecutor
│       │   ├── requests.dart       #   EditRequest types
│       │   ├── commands.dart       #   EditCommand types
│       │   ├── operations.dart     #   Operation types + inverse() for undo
│       │   ├── reactions.dart      #   EditReaction interface + built-ins
│       │   └── undo.dart           #   UndoManager (transaction grouping)
│       ├── layout/                 # L3: layout & geometry
│       │   ├── document_layout.dart
│       │   ├── block_component.dart        # BlockComponent contract + registry
│       │   └── geometry.dart               # offset<->position, caret/selection rects
│       ├── render/                 # L2/L3: per-node rendering widgets
│       │   ├── text_block.dart             # SuperText-like rich text + caret/selection layers
│       │   ├── components/                 # paragraph, heading, list, quote, code,
│       │   │   ...                         #   table, image, math, mermaid, hr, task
│       │   └── text_layout.dart            # TextLayout abstraction over RenderParagraph
│       ├── input/                  # L5: input
│       │   ├── ime.dart                    # DeltaTextInputClient implementation
│       │   ├── ime_serialization.dart      # document<->IME-text mapping
│       │   ├── shortcuts.dart              # Intents/Actions + platform key maps
│       │   ├── gestures.dart               # tap/drag/long-press -> selection
│       │   ├── input_rules.dart            # ProseMirror-style rules engine
│       │   ├── clipboard.dart              # copy/paste (markdown/html/plain flavors)
│       │   └── dnd.dart                    # drag & drop (files, blocks)
│       ├── ui/                     # L6: chrome
│       │   ├── toolbar.dart
│       │   ├── bubble_toolbar.dart
│       │   ├── slash_menu.dart
│       │   ├── block_handles.dart
│       │   ├── context_menu.dart
│       │   └── source_view.dart            # raw markdown editor + toggle
│       ├── theme/                  # L7: theming
│       │   └── editor_style.dart           # EditorStyle (ThemeExtension-friendly)
│       ├── plugins/                # L7: extensibility
│       │   ├── plugin.dart                 # EditorPlugin: bundles nodes+rules+codec+ui
│       │   └── registry.dart               # central registries
│       └── widget/                 # L7: the widget + controller
│           ├── markdown_editor.dart
│           └── controller.dart
├── example/                        # runnable demo app (all platforms)
├── test/                           # unit + widget + golden + round-trip corpus
└── specs/ (this folder, in the repo root)
```

> Note: the package lives at the repo root, so the editor source is `lib/`, the demo is
> `example/`, and these specs remain at `specs/` in the repo.

## 02.3 Dependency strategy

| Layer | Dependency | Role | Load-bearing? |
|-------|-----------|------|---------------|
| L0 | `markdown` (dart-lang) | tokenizing parser; we add custom syntaxes & our own serializer | Replaceable (could fork `dart_markdown` for source spans) |
| L2 | Flutter SDK (`dart:ui`, painting, rendering) | text shaping & geometry | Core |
| Math | `flutter_math_fork` | KaTeX rendering (inline + block) | Leaf, swappable |
| Code | `re_highlight` | syntax highlighting → `TextSpan` | Leaf, swappable |
| Clipboard | `super_clipboard` | rich clipboard across all 6 platforms | Leaf (degrades to `Clipboard`) |
| DnD | `super_drag_and_drop` | OS drag-in + internal block DnD | Leaf, optional |
| Mermaid parse | `petitparser` | native Dart grammar per diagram type | Leaf, swappable |
| Mermaid layout | `graphview` (and/or our own Sugiyama) | native graph layout for flowcharts | Leaf, swappable |
| Mermaid render | none — **our own `CustomPainter` engine** | native diagram drawing | Built in-house |

> **Hard constraint:** no dependency may host web content or run JavaScript inside the
> widget. `webview_flutter`, `flutter_inappwebview`, `flutter_tex` (MathJax), and any
> JS-interop renderer are **disallowed**. Mermaid is rendered by a native Dart engine
> (ADR-005), not a browser.

**Rules:**
- The **core** (model, markdown, editing, layout, input, render of built-in text blocks)
  depends only on the Flutter SDK + `markdown`. Everything else is behind an interface so a
  missing/failed dependency degrades gracefully, never blocks.
- Leaf dependencies are wrapped in our own interfaces (`MathRenderer`, `CodeHighlighter`,
  `ClipboardBridge`, `DiagramRenderer`) so they can be swapped or stubbed (important for
  tests and for hosts with strict dependency policies).

## 02.4 Threading & performance posture

- All editing is synchronous on the UI isolate (text editing must be); heavy work
  (large-document parse, image decode, Mermaid render) is pushed off-thread (`compute`/
  isolates) or made lazy/async with placeholders.
- Rendering is **per-block** and granular: a single ChangeNotifier-per-node pattern (à la
  appflowy) ensures only edited blocks rebuild. Off-screen blocks use a `SliverList`/
  viewport so large documents stay responsive.
- Text shaping is the dominant cost; we cache `TextLayout`/`TextPainter` per block and
  invalidate only on content/width/style change.

See [05-rendering.md](./rendering.md) for the rendering contract and
[08-cross-platform.md](./cross-platform.md) for per-platform performance notes.
