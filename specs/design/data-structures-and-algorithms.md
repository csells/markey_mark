# 13 — Data Structures & Algorithms (performance foundations)

The editor should be a showcase of *modern* text-editing engineering. This document records
the data-structure/algorithm decisions and their evidence. The headline insight from the
research: **for a block-based model where each block holds a small run of rich text but a
document can have thousands of blocks, the classic "rope vs piece-tree vs gap-buffer" debate
is the wrong question** — each block's text is small enough that a plain `String` + span list
is optimal, and the real scaling problem moves *up* to the block container and viewport.

## 13.1 Per-block text storage — plain `String` (inside our `Delta`)

**Decision.** Each text block stores its content as a `Delta` (a list of `TextRun`s, each a
plain Dart `String` + attributes). No rope/piece-tree *inside* a block.

**Why.** Ropes/piece-trees pay off only for *large* sequences with many small edits (xi
author's own conclusion; VS Code uses a piece tree for whole multi-MB files). A block of a few
hundred characters is faster as a contiguous string — O(log n) tree overhead and allocation
churn lose to a contiguous buffer at small n. Both production Flutter editors (super_editor,
appflowy) store per-block text directly. Rebuilding a short `String` per keystroke is cheap;
use `StringBuffer` for batch concatenation to avoid O(n²).

**Escape hatch.** If a single block ever holds genuinely huge content (e.g., a multi-MB code
block), that *block type alone* can adopt a rope/SumTree later — without touching the rest.

## 13.2 Block container — prefix-sum now, Fenwick/order-statistics later

**Decision.** The document is an ordered list (later tree) of blocks. We maintain index
structures over the blocks — **prefix-sum arrays** of block char-length and block height —
rebuilt lazily, for O(log n) (binary search) mapping of:
- global document offset ↔ (block, local offset)
- pixel-Y ↔ block (for hit-testing and scrolling)

**Evolution.** This is the block-level analog of VS Code's RB-tree augmented with text-length
+ line-break counts. When profiling shows it matters at thousands of blocks, upgrade the
prefix-sum to a **Fenwick (BIT) / order-statistics tree** for O(log n) updates as well as
queries. Start simple; upgrade on evidence.

## 13.3 Attribution storage — run/marker list per block

**Decision.** Inline formatting is stored as our `Delta` run list (isomorphic to
super_editor's `AttributedSpans` start/end marker list and to its flattened
`MultiAttributionSpan` form). Same-key marks don't overlap (auto-merge via normalization);
different keys overlap freely (bold over a link).

**Interval shifting.** On insert/delete at offset p, runs are split/rejoined around p and
re-normalized (merge adjacent equal-attribute runs). This is O(runs-in-block) — trivial for
small blocks. We **do not** use an interval tree: blocks are too small to need it.

## 13.4 Incremental parsing — "reparse only the edited block"

**Decision.** On each keystroke we re-parse only the **active block's** inline Markdown (a few
hundred chars) — fast enough to run synchronously per frame. Only when an edit changes *block
structure* (typing `#`, ` ``` `, list markers, blank-line split/merge) do we reconcile the
neighboring blocks. Whole-document parse (load/paste) runs **off-thread** via `compute`.

**Why not tree-sitter / a full incremental parser.** tree-sitter is C → needs FFI, which
doesn't work on Flutter web (ADR-001 forbids non-portable paths). The pure-Dart `lezer` port
is experimental (v0.1.0, no Markdown grammar). Markdown's block grammar is line/block
delimited and we already track block boundaries, so per-block reparse gives tree-sitter-like
incrementality for free, in pure Dart, on every platform. (We watch `lezer` for maturity.)

## 13.5 Layout & shaping caching

**Decision.**
1. **Per-block `TextPainter`/layout cache** keyed by `(content, width, styleVersion)`. Reuse
   across rebuilds; invalidate only the edited block. Flutter already memoizes one
   `ui.Paragraph` per `TextPainter` keyed by content+constraints and defers paint-only changes
   — we cache *above* that so unchanged blocks never re-shape.
2. **Viewport virtualization** with `ListView.builder`/`CustomScrollView` slivers — render only
   on-screen blocks. Mandatory at thousands of blocks; also bounds the cost of everything else.
3. **Memoize each block's `InlineSpan`** by its `(delta, styleVersion)` so we don't rebuild the
   span tree per keystroke.
4. **Estimated heights** for off-screen blocks so scroll extent is stable without laying them
   out; refine on scroll-in.

## 13.6 Cursor & coordinate mapping

- **Within a block:** `TextPainter.getOffsetForCaret`/`getPositionForOffset`/
  `getBoxesForSelection` — direct, block text is small.
- **Across the document:** the prefix-sum/Fenwick block index (§13.2).
- **Grapheme correctness:** Dart `String` is UTF-16; cursor movement and selection use the
  **`characters`** package (extended grapheme clusters) so we never split emoji/combining
  marks. We keep a grapheme cursor distinct from the raw UTF-16 offset.
- **Dual-mode offset mapping:** per block, a source-map between raw-Markdown offsets and
  rendered/plain-text offsets, produced as a byproduct of the per-block inline parse (§13.4) —
  this is what preserves caret position across the WYSIWYG⇄source toggle (§07.6).

## 13.7 Undo & the door to collaboration

- **Undo/redo:** the operation/transaction log with **inverse-by-construction** operations
  (§03.5, §12.2) — not snapshot-replay.
- **Future CRDT:** the same block-scoped op log is the natural substrate to later drop a
  **per-block CRDT** (YATA/Yrs-style, or Fugue/Loro) under, for real-time collaboration. We
  **design the op log to allow it but do not build on a CRDT now** — the xi-editor
  retrospective is explicit that CRDT-everywhere was over-engineering and fits history-
  dependent editing poorly.

## 13.8 Dart specifics

- `String` = UTF-16 code units; use `characters` for grapheme-aware movement.
- `StringBuffer` for batch concatenation; rebuild small block strings directly on edit.
- `compute`/isolates for whole-document parse on load/paste; per-keystroke single-block parse
  stays on the main isolate (isolate latency would exceed the parse time).
- Immature pub.dev packages noted and **avoided** as foundations: `rope` (v0.0.5),
  `piece_table` (Dart-3-incompatible), `lezer` (v0.1.0). We may revisit as they mature.

## 13.9 Prioritized adoption

**Now (slice/P0):** Delta-per-block (`String` runs) ✓ · inverse-op undo log ✓ ·
grapheme-aware cursor movement · per-block reparse · per-block layout cache + memoized spans.

**Soon (P1):** viewport virtualization · prefix-sum block index · off-thread load/paste parse
· dual-mode source maps · estimated off-screen heights.

**Later (P2+/stretch):** Fenwick/order-statistics block index · per-block CRDT for
collaboration · rope-backed storage for any genuinely huge single block.
