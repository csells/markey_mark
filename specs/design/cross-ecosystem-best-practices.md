# 14 — Cross-Ecosystem Best Practices (state of the art)

Beyond the two Flutter editors we mined ([12-bootstrap-reference.md](./bootstrap-reference.md)),
this document distills the best transferable ideas from the **whole** OSS editor/parser
landscape — ProseMirror, Lexical, CodeMirror 6/Lezer, Slate, Quill, Typora/MarkText (muya),
Obsidian, Zed/Xi, VS Code, and the parser families (cmark, markdown-it, remark/mdast,
pulldown-cmark, goldmark, markdig). Each idea is mapped to our Flutter architecture.

> **Validation:** MarkText's **muya** engine ships almost exactly our design — a tree of typed
> blocks where each editable leaf's text is tokenized into styled runs, with bidirectional
> Markdown ⇄ block-tree conversion. The xi-editor retrospective explicitly endorses
> **inverse-op undo over CRDT** for single-user editing. Our core bets are sound; the items
> below are refinements.

## 14.1 Top adopted ideas (ranked by impact on our plan)

### 1. Context-aware escaping + canonical-style serializer options — **adopt** (biggest fidelity risk)
- **Source:** remark `mdast-util-to-markdown`; `prosemirror-markdown`.
- **Idea:** don't blanket-escape characters. Maintain **"unsafe" patterns** each scoped by
  construct (`inConstruct`/`notInConstruct`) and conditioned on the **preceding/following
  char** and **at-line-start**; escape only when the context could cause a misparse (a leading
  `-` in a list context → `\-`; `!` immediately before `[` → `\!`). Expose **canonical-style
  knobs** (bullet char, emphasis `*`/`_`, fence ` ``` `/`~~~`, ATX vs setext, list-item indent,
  rule char/length) so output is stable and round-trips minimize diff churn.
- **For us:** upgrades [04-markdown-pipeline.md](./markdown-pipeline.md) §04.4–04.5. Replace the
  flat escape set with a **context-aware escaper** (current construct + before/after + at-break)
  and structure the serializer as **per-node-type handlers + a join policy + the escaper**. The
  `MarkdownStyle` knobs already specced become the canonical-style options.

### 2. Explicit position **Mapping with bias/association** — **adopt** (most common bug source)
- **Source:** ProseMirror `StepMap`/`Mapping`; the `assoc` parameter.
- **Idea:** every change yields a position map; **all** position-bearing state (caret,
  selection base/extent, decorations, future collab cursors) is remapped through it, with a
  **bias** (−1 stay before inserted text, +1 move past) resolving "where does a position at the
  edit point go."
- **For us:** add a `PositionMapping` primitive produced by each `EditTransaction` (per affected
  block: offset → offset with assoc). Route caret/selection/decoration updates through it
  instead of recomputing ad hoc. Addition to [03-document-model.md](./document-model.md) §03.5
  and [06-input-ime-and-editing.md](./input-ime-and-editing.md).

### 3. Contextual **reveal of Markdown markers near the cursor** — **adopt** (core WYSIWYG UX)
- **Source:** Obsidian Live Preview, Typora/muya.
- **Idea:** hide syntax markers and render formatting; **reveal the raw markers only for the
  block/inline span containing the caret**. Known hazard: showing/hiding markers shifts layout
  and makes the caret jump — mitigate by reserving space (dim rather than fully remove) or
  animating width, and choose reveal **granularity** (per-block vs per-inline) deliberately.
- **For us:** implement as **replace-decorations** (item 5), not model surgery. New behavior for
  [07-ux-and-chrome.md](./ux-and-chrome.md): in WYSIWYG, marker glyphs are decorations that
  collapse unless the caret is within their span.

### 4. **Normalization to a fixed point** — **adopt**
- **Source:** Lexical NodeTransforms (run repeatedly until stable); Slate `normalizeNode`.
- **Idea:** after each transaction, run normalization passes (merge adjacent equal-attribute
  runs, drop empty runs, coalesce adjacent same-type blocks, enforce schema like "list holds
  only list items") **in a loop until no further change**, so the model is always canonical
  **before** render/serialize.
- **For us:** move run-merging out of the serializer into a **model normalizer** ([03] §03.6),
  run to a fixed point as an `EditReaction`. Serialization then becomes a pure function of an
  already-canonical model.

### 5. **Decorations as a separate, mapped RangeSet (four kinds)** — **adopt**
- **Source:** CodeMirror 6 (`mark`, `widget`, `replace`, `line`; `atomicRanges`).
- **Idea:** visual overlays (syntax highlight, marker reveal/hide, search/spellcheck, collab
  carets) live **outside** the document model as a range set that is **mapped through each
  transaction**. `atomicRanges` make the caret skip over and delete inline atomic objects whole.
- **For us:** add a **decoration layer** (new section in [05-rendering.md](./rendering.md)):
  `mark` → `TextStyle` span, `widget` → `WidgetSpan`, `replace` → collapse range to a
  placeholder (this powers marker-reveal), `line` → block container attributes. Atomic ranges
  for inline image/math/mention.

### 6. **Source spans on every node/run** — **adopt**
- **Source:** goldmark segments; pulldown-cmark `into_offset_iter()`.
- **Idea:** keep byte/char offsets on every parsed node and run. Enables marker-reveal, caret
  mapping, and minimal-diff round-trips. `dart-lang/markdown`'s AST is position-light, so we
  compute spans during the per-block inline map (or adopt the position-aware `dart_markdown`).
- **For us:** strengthens the optional `SourceHints` plan in [04] §04.2 — make per-run source
  spans first-class in the mapper output.

### 7. **Widen the dirty set on boundary-affecting edits** — **adopt**
- **Source:** Lezer incremental parse; our per-block reparse.
- **Idea:** per-block reparse is right, but edits that change **block boundaries** (typing
  ` ``` ` opens a fence swallowing later lines; deleting a blank line merges paragraphs; list
  continuation) must reparse a **window of adjacent blocks**. Detect boundary-affecting edits
  and widen the dirty set.
- **For us:** refines [13-data-structures-and-algorithms.md](./data-structures-and-algorithms.md)
  §13.4.

### 8. **Immutable state snapshots + dirty-block propagation** — **adopt**
- **Source:** Lexical double-buffered EditorState.
- **Idea:** each transaction yields a new immutable document; track which blocks are dirty;
  dirtiness propagates to ancestors (a list item dirties its list); only dirty blocks
  re-parse/rebuild. Flutter's widget tree + keys is the "reconciler" — we don't build a DOM
  differ. Our `Document` is already immutable; add explicit dirty-block tracking.

### 9. **Change-as-Delta (retain/insert/delete + attributes)** — **consider**
- **Source:** Quill Delta (state *and* change are deltas; they compose).
- **Idea:** represent a block edit as a `retain n / insert run / delete n` change delta;
  `newState = compose(state, change)` and the inverse is mechanical. `retain` + attributes
  expresses "bold this range" without rewriting text.
- **For us:** our `UpdateTextOperation` currently stores before/after deltas (simple, correct).
  Moving to compose/invert change-deltas is an optimization for large blocks and collab; track
  as a P1+ refinement, not required for the slice.

### 10. **Define the schema as a Markdown-faithful subset; never silently drop content** — **adopt (policy)**
- **Source:** BlockNote/Tiptap lossy-export caution.
- **Idea:** anything Markdown can't represent (arbitrary nesting, colored text, custom attrs)
  must have an explicit **extension policy** (e.g., HTML passthrough or directive syntax),
  never a silent drop. This is the failure mode our "Markdown is the source of truth" choice is
  meant to avoid.
- **For us:** add to [01-vision-and-scope.md](./vision-and-scope.md)/[09-extensibility] — the
  schema is a subset Markdown can faithfully express; plugins that add non-representable state
  must register a serialization (HTML/directive) or are rejected.

## 14.2 Other validated patterns (already in our plan)

- **Two-phase block-then-inline parse + handler-table dispatch** (goldmark, markdown-it
  renderer rules) — matches our block-parser registry + inline visitor and per-node-type
  serializers ([04], [12]).
- **Undoable input rules** (ProseMirror) — already specced ([06] §06.4, ADR-006); ensure the
  Backspace-reverts-rule + single-undo behaviors.
- **Inverse-op undo, stay synchronous, no CRDT for single-user** (xi retrospective) — already
  our choice (ADR, [03] §03.5); keep the edit pipeline in-frame, push only heavy/optional work
  off-thread; leave the op log CRDT-ready but don't build on a CRDT.
- **Summarized block-tree for scale** (Zed SumTree, VS Code piece tree augmentation) — our
  prefix-sum→Fenwick block index ([13] §13.2); cache per-subtree summaries.
- **Profile the real hot path** (VS Code "it was `getLineContent`, not insert") — instrument
  Flutter text layout / per-block widget rebuilds before optimizing data structures.

## 14.3 Net changes to make in the spec/code (tracked)

1. Markdown serializer → **context-aware escaper + per-node handlers + join policy** ([04]).
2. Add a **`PositionMapping` with bias** to transactions; route all positions through it ([03],
   [06]).
3. Add a **decoration layer (4 kinds + atomicRanges)** and **marker-reveal-near-cursor** ([05],
   [07]).
4. Move run-merging into a **fixed-point model normalizer** reaction ([03]).
5. Carry **per-run source spans** from the mapper ([04]).
6. **Widen the reparse window** on boundary-affecting edits ([13]).
7. Add **dirty-block tracking** to the immutable document ([13]).
8. Document the **Markdown-faithful-subset + extension policy** ([01]/[09]).

Items 1–4 are correctness/UX-critical and scheduled in **P0/P1**; 5–8 follow in **P1**. The
current vertical slice already implements canonical run-merging (a subset of #4) and an escape
policy (the seed for #1); these refinements harden them to state-of-the-art.
