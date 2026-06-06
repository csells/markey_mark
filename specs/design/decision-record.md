# 00 — Architectural Decision Record

This is the ADR log: the load-bearing decisions, the options considered, and the
evidence. Each decision links back to the research in [`../research/`](../research/).

---

## ADR-001 — Render natively in Flutter; do **not** embed a web editor

**Decision.** The editor is implemented in pure Dart/Flutter. We do **not** embed
Milkdown / ProseMirror / Lexical in a WebView, despite the original research doc
([architecting-cross-platform-wysiwyg-markdown-editor-in-flutter.md](../research/architecting-cross-platform-wysiwyg-markdown-editor-in-flutter.md))
recommending exactly that.

**Why.** The product requirement is "works on **all six** Flutter platforms" (iOS,
Android, Web, Windows, macOS, Linux). A WebView core cannot meet it cleanly:

- `webview_flutter` (first-party) supports **only Android, iOS, macOS**. No Windows, no
  Linux, no Web.
- `flutter_inappwebview` is the closest "one plugin for all," but its **Linux** support
  is the least mature and **Windows** needs the WebView2 runtime; you end up juggling 2–3
  WebView backends with divergent bugs.
- Flutter **web** can host an editor via `HtmlElementView`/iframe, but **Flutter does not
  receive pointer/keyboard events that land inside the iframe** — fatal for an interactive
  editor (focus, drag-drop, overlays all fight the host).

A WebView core would therefore be reliable on ~3 platforms and fragile on the rest — the
opposite of the requirement.

**Consequences.** We must build the document model, multi-block layout, selection, and IME
ourselves (ADR-003). The payoff is uniform behavior across all targets and a widget we own
end-to-end.

---

## ADR-002 — Markdown is the **source of truth**; we own the model and the serializer

**Decision.** The canonical document is Markdown (GitHub-Flavored + extensions). The
in-memory document model is **our own**, and we **hand-write** the AST↔Markdown
serialization, backed by a golden round-trip corpus.

**Why.** `dart-lang/markdown` (the maintained parser everyone builds on) produces a
**lossy, HTML-shaped AST** (no source spans, no original markers) and ships **no
AST→Markdown serializer** (open request since 2021). Binding our model to that AST would
make Markdown an export artifact rather than the core. A perfect byte-for-byte round trip
is provably impossible from a normalizing AST (per the CommonMark author), so we target a
**stable, normalized** round trip and optionally carry **per-node source hints** (marker
char, fence style, link style) to improve fidelity where it matters.

**Consequences.** See [04-markdown-pipeline.md](./markdown-pipeline.md). We get full control
over fidelity and extensions (math, Mermaid, footnotes, tables) at the cost of owning the
serializer and its test corpus.

---

## ADR-003 — Reuse Flutter's text **painting**; replace its text **editing** widgets

**Decision.** Reuse `TextPainter` / `dart:ui Paragraph`+`ParagraphBuilder` /
`RenderParagraph` / `InlineSpan`+`WidgetSpan` for *intra-block* rich text and all
caret/selection **geometry**. Do **not** build on `EditableText`/`RenderEditable`. Build our
own document model, multi-block layout, selection model, and IME client.

**Why.** `RenderEditable` is fundamentally **one `InlineSpan`, one style run, one caret, one
IME client** — it cannot represent multiple blocks, and selection/caret cannot span multiple
`EditableText`s (each is its own IME island). This is a hard architectural ceiling, not a
configuration gap. Both `super_editor` and `appflowy_editor` independently reached the same
conclusion: keep the painting engine, replace the editing widgets.

**Options considered.**

| Option | Verdict |
|--------|---------|
| Per-block `EditableText` (one editable per block) | ❌ Selection/caret can't cross blocks; focus/IME thrash. The classic trap. |
| Fully custom `RenderObject` document layout | ✅ Viable; what we do — but reuse `TextPainter`/`Paragraph` for shaping. |
| Depend on `super_editor`/`appflowy_editor` wholesale | Rejected per ADR-004, but mine for patterns. |

---

## ADR-004 — Own the implementation top-to-bottom; **learn from**, don't depend on, prior art

**Decision.** Build our own stack, but study `super_editor` and `appflowy_editor` at the
code level and adapt their proven patterns. Use other pub.dev packages opportunistically
for **leaf** concerns (math, code highlighting, clipboard, drag-drop) where they're solid,
but never let a dependency block the architecture.

**Why.** The user's goal is a fully-owned, maximally-featured, optimal editor that proves
Flutter's capability — not a thin wrapper over a pre-1.0 package whose internal model is not
Markdown. Owning the model lets Markdown be the source of truth (ADR-002) and lets us evolve
without inheriting upstream churn. Patterns worth adapting:

- From **super_editor**: the `Editor`→`EditRequest`→`EditCommand`→`EditEvent`→reaction
  pipeline; the `DeltaTextInputClient` IME stack and document↔IME-text serialization; the
  "paint selection beneath / caret above text" layer technique (`super_text_layout`).
- From **appflowy_editor**: the `Node`/`Delta` block-tree; `Transaction`/`Operation` model
  with inverse-op undo; the `BlockComponentBuilder` registry; the **two-level Markdown
  codec** (`CustomMarkdownParser` block registry + `NodeVisitor` inline walker with an
  attribute stack); the table plugin; character/command shortcut events for input rules.

**Leaf dependencies (replaceable, not load-bearing):**

| Concern | Package | Native? all 6? |
|---------|---------|----------------|
| Math (KaTeX) | `flutter_math_fork` | ✅ pure Dart, all 6 |
| Code highlight | `re_highlight` | ✅ pure Dart, all 6 |
| Rich clipboard | `super_clipboard` | ✅ all 6 (web: paste via events) |
| Drag & drop | `super_drag_and_drop` | ✅ all 6 |
| Markdown parse | `dart-lang/markdown` | ✅ (we add custom syntaxes + our serializer) |
| Mermaid | **native Dart engine we build** (no JS/WebView); `petitparser` + `graphview`/Sugiyama + `CustomPainter` | ✅ native, all 6 (ADR-005) |

> **Hard constraint (all leaf choices):** no dependency may host web content or run
> JavaScript inside the widget. This disqualifies `webview_flutter`,
> `flutter_inappwebview`, `flutter_tex` (MathJax/WebView), JS-interop Mermaid wrappers, and
> anything that needs a DOM. Every renderer in the product is pure native Flutter.

---

## ADR-005 — Mermaid is rendered **100% natively in Dart** (no WebView, no JS) — REVISED

**Decision (revised per hard product constraint).** The widget must contain **no
web-hosted content and no JavaScript** — *everything* runs in native Flutter on all six
platforms. Therefore Mermaid is rendered by a **native Dart diagram engine we build**
(parser → layout → `CustomPainter`), exposed behind a `DiagramRenderer` interface for
pluggability/testing. There is **no WebView provider and no JS/MathJax option** anywhere in
the product. Mermaid fenced blocks (` ```mermaid `) remain a first-class node in the model
and Markdown.

**Why the change.** The original ADR-005 allowed a WebView/mermaid.js provider as a fidelity
option. The product owner has ruled out any in-widget web/JS hosting. This is consistent
with ADR-001's spirit (don't depend on WebView) and pushes us all the way to native.

**Reality check.** Mermaid.js is JS-only and there is **no production-grade native Dart
Mermaid renderer** to depend on (`flutter_mermaid` is flowchart-only and early-stage). So we
build our own native engine, in stages by diagram type, reusing native Dart building blocks
(a `petitparser` grammar per diagram type; graph layout via `graphview`/a Dart Sugiyama
implementation for flowcharts; arithmetic layout + `CustomPainter` for sequence/class/
pie/gantt). See [05-rendering.md](./rendering.md) §05.6 and [11-roadmap.md](./roadmap.md).

**Graceful degradation (never break).** Until a given diagram *type* is supported by our
engine, that block renders as a styled, read-only source card with a "diagram" badge (and a
parse-error card on malformed input). The editor itself never depends on diagram rendering
succeeding.

**Consequences.** Native Mermaid is a substantial sub-project (its own parser + layout +
renderer), sequenced after the core editor. It is the most ambitious "prove Flutter can do
it" feature in the product. No diagram code ever touches a WebView or JS engine.

---

## ADR-006 — Input "magic" via ProseMirror-style, **undoable** input rules

**Decision.** Live Markdown shortcuts (`# `→heading, `**x**`→bold, `- `→bullet,
` ``` `→code block, `> `→quote, `[]`→task, etc.) are implemented as ordered **input rules**
matched against each `TextEditingDelta` insertion, scoped to the current block's
text-before-caret. Each successful rule produces **one** transaction (one undo unit), and
**Backspace immediately after** a rule reverts the transform back to the typed text.

**Why.** This is the established pattern (`prosemirror-inputrules`; appflowy's "character
shortcut events"). The single-undo + backspace-reverts behavior is a large part of why
Markdown WYSIWYG editors feel forgiving rather than surprising.

---

## ADR-007 — Dual-mode (WYSIWYG ↔ source) over a **single source of truth**

**Decision.** The document model is canonical. WYSIWYG and raw-source views are two
**projections** of it. Toggling serializes the model to Markdown for source mode and
re-parses on the way back, **preserving caret block+offset, selection, and scroll**.

**Why.** Typora's own bug history (caret/scroll lost on mode switch, fixed in 1.13) shows
this is the easy thing to get wrong. Blocks survive both representations even when
intra-line offsets shift, so we map the caret via (block id, intra-block offset).

---

## Status summary

| ADR | Decision | Status |
|-----|----------|--------|
| 001 | Native Flutter, no WebView core | **Adopted** |
| 002 | Markdown source of truth; own model + serializer | **Adopted** |
| 003 | Reuse painting, replace editing widgets | **Adopted** |
| 004 | Own the stack; learn from super_editor/appflowy | **Adopted** |
| 005 | Mermaid optional & pluggable | **Adopted** |
| 006 | Undoable input rules | **Adopted** |
| 007 | Dual-mode over single source of truth | **Adopted** |
