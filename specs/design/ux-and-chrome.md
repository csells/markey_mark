# 07 — UX & Chrome (L6)

This layer is what makes the editor *feel* like Google Docs / Notion while staying
Markdown-backed. None of it is load-bearing for correctness; all of it is configurable and
themeable, and all of it drives the editing pipeline through `EditRequest`s.

## 07.1 The Google-Docs/Notion feel — concrete behaviors

| Behavior | Description |
|----------|-------------|
| Persistent toolbar | Top formatting bar; buttons reflect **live state** of the current selection (bold active, current block type, etc.). |
| Selection bubble toolbar | Floating mini-toolbar appears on non-empty text selection (Medium/Docs-mobile pattern). |
| Slash menu | Typing `/` at a block opens a filterable, keyboard-navigable command palette anchored to the caret. |
| Block handles | On hover, a `⠿` drag handle + `+` insert affordance appear at the block's left gutter. |
| Block selection | Select whole blocks (not just text) for move/delete/duplicate. |
| Placeholder | Empty focused document/block shows ghost text ("Type / for commands…"). |
| Smart paste | Rich paste preserves structure; plain paste strips; "paste as text" available. |
| Live formatting | Markdown input rules transform as you type (§06.4). |
| Full shortcuts | Cmd/Ctrl formatting + navigation set (§06.3). |

## 07.2 Toolbar

- A configurable list of toolbar item descriptors (not a hardcoded bar) so hosts add/remove/
  reorder items: `ToolbarItem(icon, tooltip, isActive(state), onPressed(controller))`.
- Built-ins: undo/redo, block-type dropdown (paragraph/H1–H6/quote/code), bold/italic/
  strike/code, link, bullet/ordered/task list, blockquote, insert (table/image/hr/math/
  mermaid), and the **WYSIWYG⇄Source toggle**.
- Live state: subscribes to `EditEvent`s; each item recomputes `isActive`/enabled from the
  current selection's resolved marks and block type.
- Responsive: collapses into overflow menus on narrow widths (mobile).

## 07.3 Selection bubble toolbar

- Anchored above the selection rect (below if no room), repositions on scroll/resize.
- Compact, most-common actions: bold/italic/strike/code/link + "Turn into" + "Copy as
  Markdown". Configurable item set.
- Suppressed during active IME composition and while dragging selection handles on mobile.

## 07.4 Slash command menu

- Opens **only on a real `/` keystroke** at a valid position (not on paste/programmatic
  insert/undo, not when `/` is mid-word) — the documented Notion nuance.
- Filterable type-ahead as you keep typing after `/`; `↑/↓` navigate, `Enter` selects, `Esc`
  dismisses (and the `/` reverts to literal text).
- Items: all block types, insert table/image/math/mermaid/hr, plus host-registered items.
  Items can declare `hideWhenInside` (e.g., "Bullet list" hidden when already in one).
- Each item produces an `EditRequest`. The menu is an overlay anchored to the caret rect from
  `DocumentLayout`.

## 07.5 Block handles & reordering

- Hover gutter reveals `⠿` (drag) + `+` (insert below). Touch: long-press a block to select it
  and reveal handles.
- Dragging the handle reorders the block (`MoveOperation`) with a drop indicator; `+` opens
  the slash menu to insert a new block.
- Block context actions (right-click / handle menu): duplicate, delete, turn into, move
  up/down.

## 07.6 WYSIWYG ⇄ Source mode (ADR-007)

The defining dual-mode feature. The document model is canonical; the two views are
projections.

```
            toggle ──►  serialize(model) ──► raw Markdown in a monospace source editor
WYSIWYG  ◄── toggle      parse(text) ──► model
```

- **Source view** is a focused plain-text Markdown editor (monospace, soft-wrap, optional
  Markdown syntax highlighting via `re_highlight`, line numbers optional). It edits the
  Markdown text directly; on toggle-back we parse it into the model.
- **State preserved across the toggle** (the part Typora historically got wrong):
  - **Caret:** mapped via (block id, intra-block offset). Blocks survive both
    representations even when intra-line offsets shift, so we locate the block, then the
    nearest offset within it. Going to source, we map the document caret to the character
    offset of that block+offset in the serialized text; coming back, the reverse.
  - **Selection:** same mapping for both endpoints.
  - **Scroll:** remembered per mode and restored (anchored to the caret's block if the layout
    differs).
- **Live source mode (optional, later):** a split/hybrid view that re-parses on a debounce so
  the rendered view updates as you type raw Markdown.
- **Round-trip safety:** because source mode round-trips through the same serializer/parser,
  the corpus tests (§04.6) directly protect mode-switching fidelity.

## 07.7 Placeholder, empty states, focus

- Empty document → one empty paragraph showing placeholder text when focused.
- Per-block placeholders (e.g., empty heading shows "Heading").
- Clear focus ring / caret behavior consistent with platform conventions.

## 07.8 Theming hooks

All chrome reads from `EditorStyle` (see [09-extensibility-and-theming.md](./extensibility-and-theming.md)),
which defaults to the host app's `ThemeData` so the editor looks native to the app out of the
box, and is fully overridable (toolbar colors, block text styles, code/quote/table styling,
selection color, caret color, spacing).
