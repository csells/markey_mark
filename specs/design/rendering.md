# 05 — Rendering, Layout & Geometry (L2/L3)

This layer turns the document model into pixels and answers the two geometry questions every
editor must answer: **"what document position is under this pixel?"** (hit testing) and
**"where on screen is this document position / selection?"** (caret & highlight rects) —
crucially, **across blocks**.

We reuse Flutter's text *painting* engine and replace the editing widgets (ADR-003).

## 05.1 The block-component framework

The document is rendered as a vertical list of **block components**, one per top-level node,
inside a scrollable viewport (`CustomScrollView`/`SliverList` for large docs).

```dart
abstract class BlockComponent {
  /// Builds the widget for [node]; rebuilds granularly when the node notifies.
  Widget build(BuildContext context, Node node, EditorState state);
}

/// Registry: node.type -> builder. Built-ins and plugins register here.
class BlockComponentRegistry {
  void register(String type, BlockComponent builder);
  Widget build(BuildContext context, Node node, EditorState state);
}
```

This is the appflowy `BlockComponentBuilder`/`BlockComponentRendererService` pattern — the
single most important extensibility seam: a new block type is "just" a node + a parser + a
serializer + a `BlockComponent`.

Each component exposes a small geometry contract so the document layout can stitch
cross-block selection (the super_editor `DocumentComponent` idea):

```dart
abstract class ComponentGeometry {
  NodePosition? positionAtOffset(Offset local);      // hit test within this block
  Offset offsetForPosition(NodePosition p);          // caret base point
  Rect caretRectForPosition(NodePosition p);
  List<Rect> selectionRects(NodePosition from, NodePosition to);
  NodePosition firstPosition();
  NodePosition lastPosition();
  // movement helpers for arrow-key navigation across the block's lines
}
```

## 05.2 Rich text rendering with selection-aware layers

For text blocks we render rich inline content from a `Delta` → `InlineSpan` and paint
selection **beneath** and caret **above** the glyphs. Flutter has no built-in way to draw
layout-dependent decorations around text, so we adopt super_editor's `super_text_layout`
technique: a stack of layers over a single laid-out paragraph.

```
Stack(
  layerBeneath:  selection highlight rects (from TextPainter.getBoxesForSelection)
  text:          RichText / RenderParagraph (the glyphs)
  layerAbove:    caret (blinking), composing-region underline, IME floating cursor,
                 inline-widget overlays (math, chips)
)
```

- `Delta → InlineSpan`: each run becomes a `TextSpan` with the resolved `TextStyle`; inline
  atomic objects (inline math, inline image) become `WidgetSpan` placeholders.
- Geometry comes from `TextPainter`: `getOffsetForCaret`, `getBoxesForSelection`,
  `getPositionForOffset`, `getWordBoundary`, `computeLineMetrics`, and `inlinePlaceholderBoxes`
  for positioning inline widgets.
- We wrap this in a `TextLayout`/`ProseTextLayout` abstraction so higher layers never touch
  `TextPainter` directly and so the painting backend is swappable/testable.

## 05.3 Cross-block selection & caret

`DocumentLayout` owns the list of mounted `ComponentGeometry`s in document order and
implements document-level geometry by delegating to components:

- **Hit test (Offset → DocumentPosition):** find the component whose paint bounds contain the
  Offset (or the nearest in the gap between blocks), then ask it for the `NodePosition`.
- **Caret rect (DocumentPosition → Rect):** locate the component for `nodeId`, ask for its
  caret rect, translate to document coordinates.
- **Selection highlight:** for a selection from `base` to `extent` spanning nodes A…Z, paint
  A's rects from `base` to A.last, full rects for interior nodes B…Y, and Z's rects from
  Z.first to `extent`. Atomic nodes contribute a full-bounds rect when within range.
- **Arrow-key navigation:** up/down moves by visual line within a block, then crosses to the
  vertically-nearest position in the adjacent block (preserving a "goal x" like every text
  editor).

## 05.4 Per-node component catalog

| Node | Component notes |
|------|-----------------|
| `paragraph` | rich text block (§05.2); placeholder shown when empty + focused |
| `heading` 1–6 | rich text with heading `TextStyle`; level-scaled |
| `bulleted/numbered/todo list item` | marker gutter + nested children; todo has a tappable checkbox; indentation reflects nesting depth |
| `quote` | left bar + inset; may contain nested blocks |
| `code_block` | monospace; **syntax highlighting** via `re_highlight` → spans; language label + copy button; horizontally scrollable; line numbers optional |
| `table` | **editable grid** (§05.5) |
| `image` | `Image.network`/`Image.memory` (web: bytes only); selectable as atomic; resize handles (optional); alt/title editing |
| `math` (inline) | `WidgetSpan` with `Math.tex(..., mathStyle: inline)` from `flutter_math_fork` |
| `math_block` | block `Math.tex(..., mathStyle: display)`; selectable as atomic; tap to edit TeX |
| `mermaid` | pluggable `DiagramRenderer` (§05.6) |
| `horizontal_rule` | atomic divider |
| `front_matter` | collapsed YAML card (pass-through) |

## 05.5 Editable tables

Flutter's `Table` is display-only, so the table component is a custom grid (informed by
appflowy's table plugin):

- Each cell is a `TextBlockNode` rendered by the same rich-text component → full inline
  formatting inside cells, and cell carets participate in document selection.
- Per-column **alignment** (`:--`,`:-:`,`--:`) stored on the `TableNode` and serialized to
  the GFM alignment row.
- Editing affordances: add/remove row, add/remove column, drag to resize column width,
  set column alignment — all as `Operation`s on the `TableNode`, fully undoable.
- Tab / Shift-Tab moves between cells; Enter in last cell can add a row (configurable).
- Markdown import/export via the table `BlockParser`/`NodeSerializer`.

## 05.6 Advanced content rendering details

- **Math** (`flutter_math_fork`, native, all 6 platforms): inline via `WidgetSpan`, block as
  a widget; `SelectableMath` where copy fidelity matters (experimental). Wrapped behind a
  `MathRenderer` interface for testing/swap. **No WebView/MathJax fallback** — KaTeX-class
  native rendering is the ceiling (no JS allowed).
- **Code** (`re_highlight`, native): freshest highlight.js grammars → `TextSpan`s we drop
  into our text layer; theming from `EditorStyle`. Behind a `CodeHighlighter` interface.
- **Mermaid** — **100% native Dart engine we build** (ADR-005); **no WebView, no JS**. See
  §05.8.
- **Images:** native `Image` widgets; loading/error placeholders; async decode; on web use
  bytes/network (no `Image.file`).

## 05.7 Decoration layer & contextual marker reveal (state of the art)

Visual overlays live **outside** the document model in a **decoration layer** — a range set
mapped through each transaction's `PositionMapping` (the CodeMirror 6 model). Four kinds:

- **mark** → wrap a range in a `TextStyle`/`TextSpan` (syntax highlight, search hits).
- **widget** → insert a `WidgetSpan` (inline math/mention chips, collab carets).
- **replace** → collapse a range to a placeholder/rendered glyph (this powers marker hiding).
- **line** → block-container attributes.

**Atomic ranges** make the caret skip over and delete inline atomic objects (image/math/
mention) as a unit.

**Contextual marker reveal** (the Obsidian/Typora/muya behavior, the heart of WYSIWYG-over-
Markdown): in WYSIWYG, Markdown syntax markers (`**`, `# `, list bullets) are **replace**
decorations that collapse to their rendered form, and **re-appear only for the block/inline
span containing the caret** so you can edit them. Mitigate the documented caret-jump hazard by
reserving marker space (dim rather than fully remove) or animating width, and pick reveal
granularity (per-block vs per-inline) deliberately. See
[14-cross-ecosystem-best-practices.md](./cross-ecosystem-best-practices.md) §14.1(3,5).

## 05.8 Performance

- **Granular rebuilds:** one `ChangeNotifier` per node (appflowy pattern); only edited blocks
  rebuild. The document `ChangeNotifier` drives structural changes only.
- **Viewport virtualization:** `SliverList`/`SliverChildBuilderDelegate` so off-screen blocks
  aren't laid out; large docs stay smooth.
- **Layout caching:** cache `TextLayout`/`TextPainter` per block keyed by (delta, width,
  style); invalidate on change. Text shaping is the dominant cost.
- **Async heavy work:** image decode, Mermaid layout, and large-document initial parse run
  off the UI thread (`compute`/isolates) with placeholders.

## 05.9 Native Mermaid engine (no WebView, no JS) — ADR-005

Mermaid is rendered entirely in Dart. Mermaid.js is JS-only and there is no production native
Dart renderer to depend on, so we build a staged engine with three phases per diagram type:

```
mermaid source ──► [1] Parser (petitparser grammar) ──► diagram AST/model
                ──► [2] Layout (positions, sizes, routes) ──► laid-out scene
                ──► [3] Renderer (CustomPainter) ──► native Flutter pixels
```

- **[1] Parse** — a `petitparser` grammar per diagram type (mermaid.js itself uses a separate
  jison grammar per type, so per-type grammars is the right decomposition). First token
  selects the type (`flowchart`/`graph`, `sequenceDiagram`, `classDiagram`, `stateDiagram`,
  `pie`, `gantt`, `erDiagram`, …).
- **[2] Layout** — the hard, type-specific part:
  - **Flowchart / state / ER / class relations** need **directed-graph layered (Sugiyama)
    layout** — the role `dagre` plays in mermaid.js. We use a native Dart graph-layout
    package (`graphview` provides layered/tree/force-directed algorithms) and/or our own
    Sugiyama implementation (rank assignment → ordering/crossing reduction → coordinate
    assignment → orthogonal edge routing).
  - **Sequence, pie, gantt, class boxes** are largely **arithmetic layout** (lifelines L→R,
    bars, slices, boxes) — no graph algorithm, just measurement + `CustomPainter`.
- **[3] Render** — `CustomPainter` drawing nodes (shapes from the model: rect/round/diamond/
  circle), edges (lines/curves with arrowheads — `arrow_path` or our own), and labels (laid
  out with `TextPainter`, reusing L2). Theming flows from `EditorStyle`. The painted diagram
  participates in document selection as an **atomic node** (§03.4) and is read-only inside the
  WYSIWYG view (editing happens in the fenced-code source or source mode).

**Difficulty order (drives the roadmap sequencing), validated against the Dart ecosystem:**
1. **Pie** — trivial arithmetic + arcs.
2. **Class diagram** — boxes + relationship lines.
3. **Gantt** — time-axis bars.
4. **Sequence** — lifelines + ordered messages (activations, loop/alt boxes); no graph layout.
5. **State** — graph layout but usually small; reuse Sugiyama.
6. **Flowchart (hardest)** — needs dagre-style layered layout (cycle removal → ranking →
   crossing minimization → coordinate assignment → edge routing via dummy nodes) plus
   subgraph clusters and many node shapes.

**Concrete building blocks (all native Dart, confirmed available):**
- **Parse:** `petitparser` (mature PEG combinators) — one grammar per diagram type, mirroring
  mermaid.js's per-type jison split.
- **Layout:** `graphview` ships a working pure-Dart `SugiyamaAlgorithm` (layered DAG layout,
  the dagre role) — gets flowcharts ~70%; the gaps it does *not* cover well are **subgraph
  clusters and spline edge routing**, which we implement (the deprecated pure-Dart `rwl/dagre`
  port is a useful source reference, MIT). Sequence/pie/gantt/class need no graph layout.
- **Render:** `CustomPainter` + `arrow_path` for arrowheads; labels via `TextPainter` (L2).
- **Reference:** `flutter_mermaid` (andrlange, MIT) is the only existing native attempt
  (flowchart-only, immature) — a skeleton to learn from, not a dependency.

**Graceful degradation:** any diagram *type* not yet implemented, or any parse error, renders
as a styled read-only **source card** with a "diagram" / error badge. The editor never
depends on diagram rendering succeeding, and **no code path ever touches a WebView or JS**.

All Mermaid work sits behind the `DiagramRenderer` interface (default = our native engine; a
`SourceCardDiagramRenderer` is the always-available fallback) so it is unit-testable
(parse/layout are pure Dart) and golden-testable (render).
