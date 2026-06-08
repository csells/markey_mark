# markey_mark — Design Specification

> A from-scratch, fully native, cross-platform **WYSIWYG Markdown editor** for Flutter
> that looks and feels like Google Docs, is backed by Markdown as its source of truth,
> and lets you switch fluidly between rich (WYSIWYG) and raw (source) modes — shipped as
> a single, embeddable, infinitely-extensible Flutter widget.

This folder contains the complete design specification for the editor. It is the
authoritative description of **what** we are building and **how** the pieces fit
together. Implementation should conform to these documents; when reality forces a
change, update the spec in the same PR.

## The one-paragraph thesis

The web's best WYSIWYG-markdown editors (ProseMirror/Milkdown, Lexical/MDXEditor) are
brilliant but cannot satisfy "runs natively on **all six** Flutter targets" — embedding
them requires a WebView, and `webview_flutter` is iOS/Android/macOS only, Linux has no
first-party WebView, and Flutter-web iframes swallow pointer/keyboard events. So we build
the editor **natively in Flutter**: we reuse Flutter's superb text *painting* engine
(`TextPainter`/`Paragraph`/`RenderParagraph`, `WidgetSpan` placeholders) and replace the
single-run text *editing* widgets (`EditableText`/`RenderEditable`) with our own document
model, multi-block layout, command pipeline, and `DeltaTextInputClient` IME stack — the
same conclusion both serious native Flutter editors (`super_editor`, `appflowy_editor`)
reached. Markdown is the **source of truth**: we own the document model and a configurable
AST↔Markdown serializer with a golden round-trip corpus. **Everything renders in pure native
Flutter — no WebView, no JavaScript, no web-hosted content anywhere in the widget.** Math,
code, tables, and images are native; Mermaid is rendered by a native Dart diagram engine we
build (parser → layout → `CustomPainter`), not a JS bridge.

## Reading guide

| # | Document | What it covers |
|---|----------|----------------|
| 00 | [decision-record.md](./decision-record.md) | The architectural decisions and the evidence behind them (ADR log) |
| 01 | [vision-and-scope.md](./vision-and-scope.md) | Vision, target users, feature scope, explicit non-goals, success criteria |
| 02 | [architecture.md](./architecture.md) | Layered architecture, module/package structure, dependency strategy |
| 03 | [document-model.md](./document-model.md) | Node tree, inline `Delta`/attributed text, positions, selection, transactions, undo |
| 04 | [markdown-pipeline.md](./markdown-pipeline.md) | Parse, AST mapping, serialize, source-hint fidelity, extensions, round-trip testing |
| 05 | [rendering.md](./rendering.md) | Block-component framework, text-painting reuse, caret/selection geometry, math/code/tables/images/mermaid |
| 06 | [input-ime-and-editing.md](./input-ime-and-editing.md) | `DeltaTextInputClient`, composing region, shortcuts/actions/intents, gestures, input rules, clipboard, drag-drop |
| 07 | [ux-and-chrome.md](./ux-and-chrome.md) | Google-Docs feel, toolbar, slash menu, bubble toolbar, source toggle, placeholder, smart paste |
| 08 | [cross-platform.md](./cross-platform.md) | Per-platform support matrix and concerns, accessibility, i18n/RTL |
| 09 | [extensibility-and-theming.md](./extensibility-and-theming.md) | Plugin API, public surface, theming/`EditorStyle` |
| 10 | [testing-ci-packaging.md](./testing-ci-packaging.md) | Unit/widget/golden tests, round-trip corpus, CI matrix, pub.dev packaging |
| 11 | [roadmap.md](./roadmap.md) | Milestones P0→P3, the vertical slice definition, sequencing |
| 12 | [bootstrap-reference.md](./bootstrap-reference.md) | Distilled, code-level implementation playbook mined from `super_editor` & `appflowy_editor` |
| 13 | [data-structures-and-algorithms.md](./data-structures-and-algorithms.md) | Modern text-editing data structures & algorithms (per-block storage, block index, incremental parse, layout caching, grapheme cursor, CRDT door) |
| 14 | [cross-ecosystem-best-practices.md](./cross-ecosystem-best-practices.md) | Best transferable ideas from the whole OSS landscape (ProseMirror, Lexical, CodeMirror, Slate, Quill, muya/Typora, Obsidian, remark/goldmark/markdown-it/pulldown-cmark) + gap list |
| 15 | [feature-feasibility-and-performance.md](./feature-feasibility-and-performance.md) | What can/can't be done natively cross-platform (the 5 bounded compromises) + performance/latency/resource/responsiveness budgets and their tests |
| 16 | [documentation.md](./documentation.md) | User-facing docs as a per-feature deliverable: `docs/` Markdown + generated screenshots + MkDocs → GitHub Pages pipeline |
| 17 | [unified-editing-surface.md](./unified-editing-surface.md) | ADR-008: one editor (one stream, one IME, one selection authority), stable ids, open block registry, the per-keystroke latency frontier (windowed IME, O(log n) document, per-line code layout) |
| 18 | [caret-selection-and-input.md](./caret-selection-and-input.md) | The caret/selection motor (char/word/line/doc + vertical goal-column movement across blocks), platform key bindings, and the reuse-Flutter-types plan for a11y semantics, mobile handles/magnifier, and bidi |

Supporting research lives in [`../research/`](../research/).

## Naming

- **Package / pub.dev name:** `markey_mark`
- **Primary widget:** `MarkdownEditor`
- **Controller:** `MarkdownEditorController`

These are working names; the spec is written so they can be renamed with a single
find/replace if desired.
