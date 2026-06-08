# 13 — The Unified Editing Surface (one editor, not four)

> Status: **adopted** (supersedes the per-block IME/selection assumptions in §06
> Input/IME and parts of §02 Architecture). Implemented incrementally behind the
> existing public API.

## 13.1 The problem

The first implementation grew **four disconnected editing surfaces**:

1. the main WYSIWYG canvas (a custom per-block `DeltaTextInputClient`),
2. **table cells** — each a Flutter `TextField`,
3. **code blocks** — a `TextField`,
4. **source mode** — a `TextField`.

Each has its *own* IME connection, selection, undo stack, and clipboard handling.
The symptoms are structural, not cosmetic:

- The IME mirrors only the **active block**, so a cross-block selection cannot be
  represented and had to be special-cased ("if the selection spans blocks,
  reinterpret the edit").
- Selection has **no single authority**: tap/pan, shift-click, mouse-drag
  (`Listener`), and IME selection-sync all mutate it and race (we gate them with
  `if (_mouseSelecting) return`).
- Undo, copy/cut/paste, and find/replace behave differently inside vs. outside a
  table or code block.
- Node identity is a **process-global counter** (`NodeIds.next()`), so IDs are
  not stable across reloads and **collide across peers** — fatal for
  collaboration and persistence.

## 13.2 The thesis: one logical text stream

There is **one editor**. The whole document projects to a single, flat,
read-through **document text stream** — the visible plain text of every block,
joined by block separators — and every input/selection/clipboard operation
addresses that stream by a **global offset**. A bidirectional mapping

```
globalOffset  ⇄  DocumentPosition(nodeId, localOffset)
```

is the seam between the flat stream (what the IME/selection/OS think in) and the
block tree (what the model is). Tables cells and code blocks are **regions of the
same stream**, not separate widgets; source mode is just a different *projection*
of the same document (Markdown text instead of visible text), sharing the same
selection mapped through the source offset map we already build
(`convertWithOffsets`).

```
            ┌───────────────────────── one Document ─────────────────────────┐
            │  Node tree (blocks, table cells, code, …) with STABLE ids       │
            └───────────────┬───────────────────────────────┬────────────────┘
            project (visible)│                               │project (markdown)
                             ▼                               ▼
                  DocumentText stream                  Markdown source stream
              "Title\nbody\ncell1\tcell2\n…"        "# Title\n\nbody\n\n| … |"
                             │                               │
              global offset ⇄ (nodeId, localOffset)   offset ⇄ position (source map)
                             │                               │
                             ▼                               ▼
                 ONE IME · ONE selection · ONE clipboard · ONE undo
```

### Why this collapses the four-editors problem

- **IME**: the `DeltaTextInputClient` exposes the *document* text (or a windowed
  slice) to the OS; a `TextEditingDelta` at global offset *g* maps to a block-local
  edit via the offset map. Cross-block edits stop being a special case — they are
  just an edit whose range spans a separator.
- **Selection**: one `DocumentSelection` is always expressible as a stream range
  `[g0, g1)`. Painting maps it back to per-block rects. Tables/code are inside the
  range like any other text.
- **Clipboard / find / undo**: already operate on the model; once selection is
  unified they work uniformly everywhere.

## 13.3 `DocumentText` — the stream + mapping (L1.5)

A new pure model type sits between the document (L1) and input/layout:

```dart
class DocumentText {
  final String text;                  // flattened visible text
  // segment table: each text-bearing region's [start,end) in `text`
  DocumentPosition positionAt(int globalOffset);   // → (nodeId, localOffset)
  int offsetOf(DocumentPosition position);          // inverse
  (int, int) rangeOf(DocumentSelection selection);  // → [g0,g1)
  DocumentSelection selectionOf(int base, int extent);
}
```

Invariants (property-tested):
- `offsetOf(positionAt(g)) == g` for every valid `g`.
- The segment table is total and ordered; separators occupy exactly one offset.
- Building it is O(n) in blocks; lookups are O(log n) (binary search the table).

This **generalizes `convertWithOffsets`** (which maps Markdown source offsets) to
the *visible* text used for editing. The two maps are siblings: one for source
mode, one for WYSIWYG.

## 13.4 Stable node identity (L1)

`NodeIds.next()` (a global counter) is replaced by **collision-free, stable
ids**: a per-document/site random base plus a monotonic suffix, so

- ids survive serialize→parse→reload (persistence), and
- two peers never mint the same id (collaboration convergence).

Block ordering for concurrent reorders uses **fractional-index keys** (insert
between `a` and `b` without renumbering), which makes reorder/insert operations
*mergeable* instead of index-based.

## 13.5 Open block set: the `BlockSpec` registry (L0–L3)

The closed `sealed`+`switch` block set (replicated across decoder, encoder,
renderer, HTML) becomes a **registry of `BlockSpec`s**. Each block declares, in
one place: its node type, how to decode/encode Markdown, how to render (WYSIWYG +
HTML), and whether it contributes text to the stream. The pipeline is data-driven
off the registry, so a new block (or a third-party plugin) is **one
registration**, not five edits.

## 13.6 Migration plan (incremental, test-first)

Each step ships behind the existing public API with green tests:

1. ✅ **`DocumentText` stream + mapping** (pure model) + property tests
   (`document_text.dart`, exact round-trip).
2. ✅ **Stable ids** via `NodeIdGenerator` (per-site prefix, collision-free
   across peers). *Fractional-index ordering for mergeable reorders is still
   open.*
3. ✅ **Selection authority**: every selection change goes through controller
   intents (`placeCaretAt` / `extendSelectionTo` / `selectByOffsets` /
   `selectionOffsets`) expressed in `DocumentText` global offsets; gestures and
   the IME call these instead of building `DocumentSelection`s ad hoc.
4. ✅ **IME on the stream**: `updateEditingValue` / `updateEditingValueWithDeltas`
   map deltas through `DocumentText`; the cross-block special-cases are gone —
   deleting a separator merges blocks, inserting a newline splits one, natively.
5. ✅ **Tables & code as regions**: **code blocks** join the stream and edit
   through the shared command pipeline (Enter inserts a literal newline),
   rendering with the unified caret. **Table cells** are now caret-based
   sub-editors via a table-aware `TableCellPosition`: tapping a cell places a
   cell caret, the IME *windows* to that single cell, and edits route through
   the unified commands (cells never merge across boundaries — the 2D grid
   stays intact). The per-cell `TextField` is gone. *(Cross-cell / cell↔body
   drag-selection — selecting a rectangular cell range — is a further
   refinement; within-cell selection and all editing are unified.)*
6. ✅ **Open block set**: `CustomBlockNode` + `BlockRegistry` render extension
   point (`block_registry.dart`). *Decode/encode registration builds on the same
   seam and is still open.*

Status: **steps 1–6 are implemented.** One IME, one selection authority, one
identity scheme, one document, one open block model — and every WYSIWYG editing
surface (paragraphs, headings, lists, quotes, code blocks, table cells) now
shares the same caret/IME/command/undo machinery. Source mode remains a
deliberate alternate *projection* (sharing selection via the source offset map).
Markdown stays canonical; no WebView/JavaScript.

Remaining refinements (smaller, tracked): fractional-index block ordering for
mergeable concurrent reorders; decode/encode registration for custom blocks; and
rectangular cross-cell / cell↔body drag-selection.

## 13.7 Latency requirement: never reprocess the whole document per keystroke

**Requirement (enforced by tests):** a keystroke must cost **O(active block)**,
not O(document) — typing in a 4,000-block document is no slower than in a
20-block one.

**Why this was at risk.** The first cut of the unified stream had the IME mirror
the *entire* document (`DocumentText.of(wholeDoc)`) and re-flatten it on every
keystroke, and the `markdown` getter re-serialized the whole document on every
read. Both are O(document) on the hot path — unacceptable.

**How best-in-class editors avoid it (research):**
- **CodeMirror 6** — the document is an immutable rope (`Text`) with structural
  sharing; edits are positional `ChangeSet`s; only affected tree portions and
  the viewport update. (codemirror/state README.)
- **ProseMirror** — a persistent immutable node tree; transactions are steps; the
  view redraws only the *changed* nodes.
- **Lexical** — a dirty-node reconciler diffs prev/next `EditorState` and touches
  only dirty leaves/elements.
- **super_editor** — serializes only the *selected node(s)* to the IME (plus a
  hidden leading char to detect start-of-block backspace), never the whole doc.

**What we do.** The model is already immutable with structural sharing (an edit
replaces one node; the rest keep identity). On top of that:
1. **Windowed IME** — the IME mirrors only the selection's block span plus one
   editable neighbor each side (`_imeWindow`), so backspace-at-start still merges
   and Enter splits, while a keystroke flattens O(active block).
2. **Memoized serialization** — `markdown` is cached by document identity, so
   repeated reads don't re-serialize.

**Gates (deterministic UI tests, not timing-flaky):**
`DocumentText.debugFlattenedChars` proves a keystroke flattens O(block) in a
2,000-block doc; `Markdown.debugSerializeCount` proves serialization is memoized;
the IME value is asserted to be a bounded window (active ± 1), never distant
blocks; and a wall-clock test asserts typing in a 4,000-block doc stays ~constant
vs. a 20-block doc.

**The document itself is now O(log n) per edit.** `Document` is backed by a
`PersistentList` (an immutable implicit treap): `replace`/`insert`/`removeAt`/
`get` are O(log n) with structural sharing — an edit never copies the whole
node sequence. An `id→index` cache is carried across structure-preserving
replaces, so `indexOfId`/`nodeById` are O(1) on the hot path (no per-keystroke
linear scan); `nodeAt(i)`/`length` (O(log n)/O(1)) are used on the hot path
instead of materializing `nodes`. Gated by `document_perf_test`: typing in a
**100k-block** document is ~as fast as in a 200-block one, and typing adds no
linear id scans after priming (`Document.debugIdScans`).

*Earlier mistake, corrected:* the first "latency fixed" pass only removed the
expensive O(n) (whole-document string flatten) and a 4k-block timing test gave
false confidence; the flat-`List` `indexOfId` scans and copy-on-write were still
O(n) per keystroke. Now genuinely O(log n).
