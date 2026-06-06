# 11 — Roadmap & Milestones

Sequencing from "prove the architecture" to "the most full-featured native Markdown editor in
the world." Each milestone is shippable and testable. Constraint throughout: **100% native
Flutter, no WebView, no JavaScript** (ADR-001, ADR-005).

## The vertical slice (this session's target)

Goal: prove the whole pipeline end-to-end on a tiny node set so every layer is exercised.

**Scope:** `paragraph` + `heading` blocks; `bold` + `italic` inline marks.

**Path proven:** `model → markdown round-trip → render → edit → input rule → source toggle`.

**Deliverables:**
- Package scaffold (`pubspec.yaml`, `analysis_options.yaml`, `lib/` module layout, `example/`).
- **Model:** `Delta`/`TextInsert`, `Node`/`ParagraphNode`/`HeadingNode`, `Document`,
  `DocumentPosition`/`TextNodePosition`, `DocumentSelection`, the 4 `Operation`s + `inverse()`,
  `Transaction`, `Editor.apply` + `UndoManager`.
- **Markdown:** parse (paragraph/heading + bold/italic via `dart-lang/markdown`) and our own
  serializer; merge-adjacent-runs normalization; **round-trip corpus tests** (idempotence +
  AST-stability).
- **Render:** rich-text block components for paragraph/heading (Delta→`InlineSpan`); a caret
  + selection layer (SuperText-style) for the focused block.
- **Edit:** custom `DeltaTextInputClient` for the active block; insert/delete; Enter splits a
  block; Backspace at start merges (leading-placeholder hack); toolbar bold/italic toggle.
- **Input rules:** `# `→heading and `**x**`→bold, each a single undo unit with
  backspace-revert.
- **Source toggle:** WYSIWYG ⇄ raw Markdown (`MarkdownEditor` + `MarkdownEditorController`),
  preserving content.
- **Tests green + analyzer clean**; `example/` app runs.

**Explicitly deferred from the slice** (tracked below): cross-block selection, lists/quotes/
code/tables/images/math/mermaid, slash menu, drag handles, full platform IME polish.

---

## P0 — Foundation (core that everything builds on)

- Full document model (all node types' classes; tree; schema invariants; normalization).
- Editing pipeline: `EditRequest`→`EditCommand`→`Transaction`→`Operation`→reactions→events;
  inverse-op undo with grouping; **explicit, unit-tested path rebasing**.
- Markdown pipeline: block-parser registry + inline visitor (decode); per-node + per-mark
  serializer (encode); source-hints scaffold; the round-trip corpus harness.
- Layout & geometry: `DocumentLayout`, `BlockComponent` registry, `ComponentGeometry`,
  cross-block hit-testing & caret/selection rects.
- Text rendering: `TextLayout` abstraction + SuperText-style layered caret/selection.
- IME: `DeltaTextInputClient`, document↔IME serialization, composing region, leading-
  placeholder hack; the per-platform quirks module.
- Hardware keys: `Shortcuts/Actions/Intent` baseline set.
- The `MarkdownEditor` widget + `MarkdownEditorController` + `EditorStyle` from `ThemeData`.

## P1 — The full block & inline set + "feel"

- Blocks: bullet/ordered/**task** lists (nested), block quotes (nested), fenced/indented code
  with `re_highlight`, horizontal rule, images, **GFM tables (editable)**, inline + block
  **math** (`flutter_math_fork`), footnotes, front-matter pass-through.
- Inline: strikethrough, inline code, links/autolinks, inline math.
- Live input rules for the whole set (block + inline); linkify.
- Cross-block selection + delete/merge/split correctness.
- Clipboard: markdown/html/plain flavors, smart paste, paste-as-text (`super_clipboard`).
- Drag & drop: OS files + block reordering (`super_drag_and_drop`).
- Chrome: persistent toolbar (live state), selection bubble toolbar, slash menu, block hover
  handles, placeholder, context menus (`AdaptiveTextSelectionToolbar`).
- Source mode polish: caret/selection/scroll preservation across toggle; optional source
  syntax highlighting.

## P2 — Native Mermaid engine (the flagship "Flutter can do it all" sub-project)

Staged by diagram type (difficulty order, §05.8), all behind `DiagramRenderer`, all native:

1. Engine skeleton: `petitparser` per-type grammar dispatch, diagram AST, `CustomPainter`
   scene renderer, atomic-node integration, source-card fallback. Prototype with **pie** to
   validate parse→AST→paint cheaply.
2. **class** diagram, **gantt**, **sequence** (arithmetic layout).
3. **state** diagram (reuse `graphview` Sugiyama).
4. **flowchart** (hardest): layered layout on `graphview`'s Sugiyama + our subgraph-cluster
   and edge-routing work; full node-shape set.
5. ER and remaining types; theming via `EditorStyle`; golden tests per type.

## P3 — Productionization & differentiation

- Accessibility semantics tree; RTL/bidi; font scaling; localization delegate.
- Extensibility hardening: public plugin API + "plugin author guide" (custom block
  end-to-end) in `example/`; `CorePlugin` proves the API is sufficient.
- Performance: viewport virtualization, layout caching, off-thread parse/layout, large-doc
  benchmarks.
- Testing/CI: full unit/widget/golden suites; per-platform goldens (`alchemist`); GH Actions
  matrix (ubuntu/macos/windows + web build); `pana`/publish dry-run.
- Docs, `CHANGELOG`, example gallery; first pub.dev release.

## Stretch / future (architecture already accommodates)

- Real-time collaboration (CRDT/OT) over the serializable operation log (the L4 seam).
- Definition lists, emoji shortcodes, callouts/admonitions, comments/annotations,
  track-changes, find-&-replace, export (HTML/PDF via native rendering).

## Sequencing rationale

P0 then the **vertical slice inside P0** de-risks the hardest unknowns (custom IME, caret,
round-trip) before breadth. P1 delivers a genuinely complete editor. P2 (native Mermaid) is
isolated as its own sub-project so it can proceed in parallel without blocking the editor and
is the strongest demonstration of the native-only thesis. P3 makes it publishable and
world-class.
