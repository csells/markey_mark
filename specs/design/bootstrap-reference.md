# 12 — Implementation Bootstrap Reference (patterns mined from prior art)

This is the distilled, code-level playbook for our own implementation, drawn from deep dives
of `super_editor` and `appflowy_editor`. We **adopt the patterns, write our own code.** Each
entry says what to copy, what to change, and the source it came from.

> Provenance: super_editor (github.com/superlistapp/super_editor) and appflowy_editor
> (github.com/AppFlowy-IO/appflowy-editor), `main` branches, mid-2026.

## 12.1 Inline text representation — adopt the run/marker duality

Two equivalent designs exist; we use **`Delta` (appflowy)** as the stored form because it
maps 1:1 to our Markdown codec, and treat it as isomorphic to super_editor's
**`MultiAttributionSpan`** (the flattened run form) for rendering and serialization.

- **`Delta`** = ordered `insert(text, attributes)` ops (we only need inserts for storage;
  `retain`/`delete` are used transiently to *build* edits). Provides `compose`, `invert`,
  `diff`, `slice` — the OT primitives that make undo and IME diffing cheap (appflowy
  `text_delta.dart`).
- super_editor stores inline styles as **`AttributedSpans` markers** (start/end pairs) and
  flattens via `collapseSpans()` → `MultiAttributionSpan{attributions, start, end}` — one
  uniform-style run per span. **A `Delta` of insert ops *is* exactly this run list.** We get
  the praised "order-stable serialization for overlapping/nested styles" for free by walking
  the delta runs in order.
- `Attribution.canMergeWith` (super_editor): bold+bold merge, link(a)+link(b) do not. We keep
  this rule when normalizing adjacent runs (don't merge runs with conflicting link/color).

**Takeaway:** store `Delta`; render/serialize by walking runs; normalize adjacent
equal-attribute runs after every transaction (our §03.6 invariant).

## 12.2 Operations — adopt appflowy's inverse-by-construction (NOT snapshot-replay)

Four operations, each invertible with **zero document access** (appflowy `operation.dart`):

| Op | Carries | `inverse()` |
|----|---------|-------------|
| `InsertOperation(path, nodes)` | the inserted nodes | `DeleteOperation(path, nodes)` |
| `DeleteOperation(path, nodes)` | **the removed nodes** | `InsertOperation(path, nodes)` |
| `UpdateOperation(path, after, before)` | both attr maps | `UpdateOperation(path, before, after)` |
| `UpdateTextOperation(path, delta, inverted)` | both deltas | `UpdateTextOperation(path, inverted, delta)` |

- Undo = pop transaction, invert each op **in reverse order**, swap before/after selection,
  re-apply (appflowy `undo_manager.dart` / `HistoryItem.toTransaction`).
- **Reject super_editor's full snapshot-replay undo** (O(history), memory-heavy) — the agent
  flagged it; inverse ops are cleaner and what we want.
- **Watch the path-rebasing footgun:** appflowy hides path transformation inside
  `Transaction.add()` (rebasing queued op paths against each other, merging adjacent
  `UpdateTextOperation`s on the same path). We make this **explicit and unit-tested** rather
  than buried — it's the trickiest, least-documented logic and easy to get subtly wrong.

## 12.3 Positions — adopt super_editor's `UpstreamDownstreamNodePosition` for atomic blocks

Text blocks use `TextNodePosition(offset, affinity)`. Atomic blocks (image, hr, math_block,
mermaid) use a **binary** position with exactly three selection states — caret-before,
caret-after, whole-node-selected (super_editor `selection_upstream_downstream.dart`). This is
the cleanest known solution to "select/caret around an image" and slots into the same
base/extent machinery as text. Copy it.

Block-type as **metadata, not subclass** where natural (super_editor: a header is a
`ParagraphNode` with `metadata['blockType']=h2`) — makes "turn paragraph into heading" an
attribute edit, not a node swap. We use this for paragraph↔heading↔quote; we keep distinct
classes only where behavior/fields genuinely differ (code, table, image, math).

## 12.4 The editing pipeline — adopt super_editor's request→command→event→reaction

```
editor.execute([EditRequest])
  startTransaction()
  for req: command = firstNonNull(requestHandlers(req)); executor.execute(command)
           command mutates editables, logChanges([EditEvent]); may prepend/append commands
  reactions.modifyContent(...)   // same transaction (normalization, input rules)
  endTransaction()               // editables fire ONE typed change log
  reactions.react(...)           // may open a NEW transaction (linkify, etc.)
  listeners.onEdit(changeLog)    // toolbar live-state, IME sync, host autosave
```

- **`EditContext` service locator** with keys `"document"`, `"composer"` (selection +
  pending/“toggled” attributions for the next typed char), `"layout"`.
- **Document fires ONE typed change log per transaction** (super_editor `Editable.onTransactionEnd`
  → `DocumentChangeLog` of `NodeInserted/Removed/Moved/Changed`), not per mutation — widgets
  rebuild only nodes whose id is in the log. Combine with appflowy's **per-node
  `ChangeNotifier` + `ChangeNotifierProvider`** for granular rebuilds.
- **Input rules / markdown shortcuts are reactions** (super_editor
  `default_document_editor_reactions.dart`): regex against just-typed text → dispatch
  follow-up requests, all in one transaction = one undo unit. NB: super_editor ships only
  *block-prefix* reactions; **live inline `**bold**` is net-new for us** (appflowy does it via
  character-shortcut events — we generalize to a regex rules engine, §06.4).

## 12.5 Layered text rendering — adopt super_editor's `SuperText` two-pass technique

Flutter can't let a sibling see another sibling's text layout, so to paint selection *under*
and caret *over* glyphs we use a custom two-pass `RenderObject` (super_editor
`super_text_layout`):

```
RenderObject children [background, text, foreground]:
  performLayout: text.layout(constraints, parentUsesSize:true);
                 capture laid-out paragraph; layout background/foreground tight to text.size
  paint:         background (selection rects) → text (glyphs) → foreground (caret/underline)
```

- Expose a `TextLayout` abstraction over `RenderParagraph`/`TextPainter` (super_editor
  `text_layout.dart`): `getOffsetForCaret`, `getHeightForCaret`, `getBoxesForSelection`,
  `getPositionForOffset`, `getWordSelectionAt`, `getPositionOneLineUp/Down` (goal-x arrow
  nav), `getPositionAtStartOfLine/EndOfLine`. Higher layers never touch `TextPainter`.
- Caret blink = opacity-only repaint in the foreground layer (don't relayout on blink).
- Selection highlight = `getBoxesForSelection(boxHeightStyle: max)` → one rounded rect per
  wrapped line.

## 12.6 Cross-block geometry — adopt the two-level delegation

`DocumentLayout` knows where each block is; each block's `ComponentGeometry` knows geometry
inside itself (super_editor `document_layout.dart` + `DocumentComponent`; appflowy
`SelectableMixin`). Stitch:

- **Offset→position:** binary-search blocks by y (both editors do this), convert to local,
  ask the block.
- **Position→caret rect:** find block, ask for local caret rect, translate to doc coords.
- **Cross-block selection:** first block = base→its end; middle blocks = full; last block =
  its start→extent; **paint per-block rects that visually join** (neither editor paints one
  global highlight).
- Caveat (appflowy): reaching `RenderParagraph` via `GlobalKey.findRenderObject()` is fragile
  across Flutter versions; isolate it behind our `TextLayout` so upgrades touch one file.

## 12.7 IME — adopt the serializer + the leading-placeholder hack

(super_editor `document_serialization.dart` / `document_delta_editing.dart`; appflowy
`delta_input_service.dart`.)

- Maintain a flat **IME view** of the active region: text nodes joined by `\n`, each atomic
  node a single placeholder char; keep two maps (IME-range↔node) for O(1) translation.
- **Leading-placeholder hack (critical):** IMEs swallow backspace at offset 0, so you never
  learn the user pressed backspace at a node's start (needed to merge with the previous
  block). When the caret is collapsed at a node's beginning, **prepend an invisible char** to
  the IME text so offset 0 isn't the true start; a real deletion delta then appears and is
  interpreted as "merge upstream." Both editors independently do this.
- Translate `TextEditingDelta{Insertion,Deletion,Replacement,NonTextUpdate}` → `EditRequest`s;
  rebuild the serializer after structural edits; recompute & **clamp the composing region**
  after a reaction rewrites text (it can point past the new text).
- **Never reset the composing region speculatively from a listener** → Gboard infinite loop.
- Budget per-platform branches: Android newline arrives as `performAction`, iOS tab→indent,
  iOS "select all" arrives as a NonTextUpdate to expand, macOS key bindings as
  `performSelector` selectors, and **web** needs its own keyboard/composing fixups.

## 12.8 Hardware keys — use `Shortcuts/Actions/Intent` (our choice), informed by their action lists

super_editor uses a custom `KeyEvent` chain-of-responsibility (~32 platform-aware functions);
appflowy uses `CommandShortcutEvent` with `'ctrl+b,cmd+b'` strings + per-OS overrides. We use
Flutter's `Shortcuts/Actions/Intent` (host-remappable, idiomatic) but **mine their action
lists** for the full set we must cover: arrows + goal-x vertical motion, home/end, word/line
delete, select-all, copy/cut/paste, formatting, escape-collapses-selection, and the
web/per-OS variants they had to add.

## 12.9 Markdown codec — adopt appflowy's two-stage, symmetric design

(appflowy `document_markdown_decoder.dart` / `delta_markdown_decoder.dart` / encoders.)

- **Decode blocks:** `dart-lang/markdown` (GFM + our custom inline syntaxes) → `md.Node` tree;
  offer each node to an **ordered list of block parsers, first non-empty wins** (order *is*
  priority — no numeric field).
- **Decode inline:** a `NodeVisitor` with an **attribute stack** — `visitElementBefore` pushes
  (`strong`→bold…), `visitText` snapshots the stack into a `Delta` run, `visitElementAfter`
  pops. Nested marks compose correctly.
- **Encode:** symmetric `NodeSerializer` per `node.type` (match by id) for blocks; walk the
  `Delta` runs emitting markers for inline.
- **Custom blocks round-trip with zero schema change:** store payload as JSON in
  `attributes`; register a parser (decode) + serializer (encode) pair. Inline math = a
  placeholder run carrying the TeX in an attribute (appflowy `FormulaInlineSyntax`).
- **Improve on their encoder:** appflowy re-emits markers per insert and can produce
  non-canonical `**a****b**`; our serializer **merges adjacent equal-attribute runs first**
  (§03.6) so output is canonical. This is why our round-trip corpus (§04.6) checks
  idempotence.

## 12.10 Tables — adopt appflowy's explicit-position cell model

A `table` node with `rowsLen`/`colsLen`; cells are child nodes tagged with
`rowPosition`/`colPosition` (+ width/height); each cell's content is a normal paragraph node,
so **cell editing reuses the entire text/selection stack unchanged** (appflowy
`table_node.dart`). Add/remove row/col = insert/delete cell nodes + renumber position attrs.
Import/export via the table parser/serializer pair. Prefer their **V2** parser designs.

## 12.11 Package layering — adopt super_editor's clean separation

super_editor's reusable layering is its best structural idea: `attributed_text` (pure Dart) ←
`super_text_layout` (Flutter widgets, no document concept) ← editor. We mirror it internally
as `model` (pure Dart) → `render`/`layout` (Flutter, no editing) → `editing`/`input` → widget,
so the pure-Dart core (model + markdown) is testable in isolation with no Flutter dependency.

## 12.12 The "do-it-better" list (where we improve on both)

1. **Markdown as the true source of truth** (both treat it as import/export) → canonical model
   + owned serializer + round-trip corpus.
2. **Canonical inline serialization** (merge runs) → no `**a****b**`.
3. **Explicit, tested path rebasing** (appflowy buries it in `add()`).
4. **Inverse-op undo** (reject super_editor snapshot-replay).
5. **Live inline input rules** (neither ships block+inline live conversion uniformly).
6. **One IME-quirk module** with platform tests (both scatter platform `if`s through the
   hottest code).
7. **Tree model** for true list/quote/table nesting (super_editor is a flat list + indent).
