# Gap Analysis — implementation vs. specs & plans

> Fresh-eyes review of the `markey_mark` implementation against the design specs
> (`specs/design/*`) and roadmap. Date: 2026-06. Scope: what's built, what's
> partial, what's missing — and an honest read on "best end-to-end Markdown
> editor on any platform."

## 1. Constraints (the non-negotiables) — ✅ held

- **100% native Flutter, no WebView, no JavaScript** — held everywhere, including
  Mermaid (10 native diagram renderers), code highlighting (pure-Dart line
  tokenizer), math (`flutter_math_fork`), and clipboard/DnD (`super_clipboard`/
  `super_drag_and_drop`, native).
- **Markdown is canonical** — the document serializes to Markdown; source mode is
  a projection of the same model; round-trip corpus tests (CommonMark + GFM).

## 2. Architecture — ✅ the "one editor" thesis is real

The §13 unification is implemented: one `DocumentText` stream, one IME
(`DeltaTextInputClient`), one selection authority, one command/undo pipeline,
stable node ids, and an open block registry. Tables and code blocks are regions
of the one editor, not separate `TextField`s. Source mode shares selection via
the offset map.

## 3. Performance — ✅ strict gates in place

- Per-keystroke is **O(log n)** in block count (`PersistentList` treap) with an
  O(1) id→index cache; the IME is **windowed** (flattens O(active block)); the
  `markdown` getter is memoized.
- Intra-block: code blocks lay out **per line**, and both shaping *and*
  tokenizing are incremental (O(changed line)).
- Gated by deterministic counters (`debugFlattenedChars`, `debugSerializeCount`,
  `debugIdScans`, `debugShapedChars`, `debugTokenizedChars`) + wall-clock tests
  at 100k blocks / multi-thousand-line code blocks.
- Off-main-thread parsing is available (`Markdown.parseAsync`, via `compute`), so
  a huge initial load doesn't jank the UI; viewport virtualization relies on
  `ListView`. (Off-thread *layout* remains future.)

## 4. Editing feel — ✅ brought to native-field parity this cycle

- **Caret/selection motor**: character (grapheme), word, logical & **visual**
  line, document; vertical up/down with a preserved goal column; works across
  paragraphs, code blocks, and table cells. Shift-extend for every move. Word/
  line deletion. Platform-aware key bindings (macOS vs others).
- **Accessibility**: the surface is a semantic text field (`isTextField`, live
  `textSelection`, `setSelection` + per-character/per-word cursor actions) plus
  the read-side header/label/image roles.
- **Mobile**: draggable selection handles + magnifier, scroll-following.
- **RTL/bidi**: per-paragraph base direction; **per-run** visual arrow movement
  (mixed LTR/RTL paragraphs move visually in each run).
- **OS font scaling**: `MediaQuery.textScaler` is applied to every painter
  (paragraphs, code, cells), so accessibility font sizes take effect.
- **Localization**: all chrome strings come from `MarkdownEditorLabels`.
- **Table cells**: Tab / Shift+Tab navigate cells (wrapping; Tab past the end
  appends a row).

### Remaining editing gaps
- **Rectangular cross-cell table selection** (selecting a 2-D block of cells) is
  not implemented (within-cell editing/selection and Tab navigation are).
- **Toolbar**: the formatting bubble and the clipboard context menu coexist by
  design; not consolidated into one adaptive surface.

## 5. Collaboration — ✅ convergent, wired into the runtime

`OtCollaborationSession` is a Jupiter-style relay that wires the OT transforms
into the runtime: peers edit **concurrently** and converge (the raw `applyRemote`
path would diverge). Different-block edits merge losslessly; concurrent
same-block **insertions** merge character-by-character (both typists keep their
text); other same-block conflicts fall back to deterministic LWW. Mergeable
ordering is available via `FractionalIndex.keyBetween` (insert between any two
keys without renumbering).

*Remaining:* a full Delta-level OT (so concurrent same-block *deletes/formatting*
also merge instead of LWW) and a concrete network transport beyond the in-process
relay.

## 6. Extensibility — ✅ render + Markdown round-trip

`CustomBlockNode` + `BlockRegistry` (render) now pair with `CustomBlockCodec` /
`BlockCodecs` for Markdown **decode/encode**, so third-party blocks round-trip
(`Markdown.parse`/`serialize` take optional codecs). *Remaining:* a published
"plugin author guide" / `CorePlugin` end-to-end example.

## 7. Testing & docs

- **~94%+ line coverage** (unit + widget), analyzer clean, `dart format`-clean.
  New this program: clipboard/drop, code-layout fallback, positions, caret-motor
  edges, font scaling, localization, fractional index (property test), custom-
  block codecs, OT convergence, PDF export, off-thread parse. Lowest remaining is
  `markdown_editor.dart` (the 2.3k-line widget's device-only DnD/`super_clipboard`
  branches).
- **Docs**: per-feature Markdown in `docs/` + a screenshot generator + MkDocs;
  this program added caret-motor/RTL/mobile/a11y/keyboard, localization, PDF +
  off-thread, table-cell-nav, and collaboration docs.
- **Golden tests**: `test/golden/` reference-image regression tests (deterministic
  test font) with committed references. **CI**: a multi-OS matrix
  (`docs/ci/ci.yml`) running analyze + format + tests + goldens, a web build, and
  a `pub publish --dry-run`. PDF export is implemented (`Markdown.toPdf`,
  pure-Dart, no deps).

## 8. The "god widget"

`_MarkdownEditorState` is ~2.3k lines and owns IME, gestures, layout caches,
find/replace, DnD, clipboard, context menu, slash menu, source mode, painting,
keyboard, handles, and semantics. It works and is well-tested behaviorally, but
it's the highest-risk file to change and the hardest to unit-test in isolation.
The motor/semantics extraction this cycle reduced its logic surface; further
extraction (an IME controller, a gesture→intent layer) is the main structural
debt remaining.

## 9. Honest verdict

The editor is strong end-to-end: native-only, Markdown-canonical, one unified
editing surface, O(log n) editing with incremental intra-block layout, and
native-parity caret/keyboard/selection, accessibility (incl. font scaling),
mobile handles/magnifier, per-run RTL, localization, table-cell Tab navigation,
**convergent** collaboration (with character-level same-block insertion merge),
custom-block Markdown round-trip, PDF export, off-thread parsing, golden tests,
and a multi-OS CI matrix — all from the prior gap list, now implemented and
tested.

The honest **remaining** items are smaller and scoped: a full Delta-level OT (so
concurrent same-block *deletes/formatting* merge rather than LWW) and a real
network transport; rectangular cross-cell table selection; a published plugin
author guide; off-thread *layout*; and the structural cleanup of the ~2.3k-line
editor god-widget (extract an IME controller and a gesture→intent layer). None
are architectural blockers.
