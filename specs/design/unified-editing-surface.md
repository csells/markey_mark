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

1. **`DocumentText` stream + mapping** (pure model) + property tests. ✅ seam.
2. **Stable ids** + fractional-index ordering; round-trip + merge tests.
3. **Selection authority**: route all selection mutations through one
   `SelectionController` that speaks global offsets; gestures become thin.
4. **IME on the stream**: the input client maps deltas via `DocumentText`;
   delete the cross-block special-cases.
5. **Tables & code as regions**: render their text through the same stream so a
   selection can enter/cross them; retire their private `TextField`s.
6. **`BlockSpec` registry**: collapse the per-type switches.

The end state: **one IME, one selection, one undo, one clipboard, one document**
— with Markdown still the canonical form and no WebView/JavaScript.
