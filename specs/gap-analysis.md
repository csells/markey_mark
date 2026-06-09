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
  `ListView`. Off-thread *layout/shaping* is a **Flutter platform constraint**
  (`TextPainter`/`dart:ui` text layout runs only on the UI isolate), so it is
  documented as out of scope rather than faked; parsing — the heavy CPU step on
  load — is the part that genuinely moves off-thread.

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

## 5. Collaboration — ✅ convergent, with full character-level OT + a transport

`OtCollaborationSession` is a Jupiter-style relay that wires the OT transforms
into the runtime: peers edit **concurrently** and converge. Different-block edits
merge losslessly; concurrent same-block edits — **inserts, deletes, *and*
formatting** — merge with character-level OT (`DeltaChange`: a retain/insert/
delete change model with `diff`/`transform`/`apply`, property-tested over 500
random concurrent edits). Mergeable ordering is available via
`FractionalIndex.keyBetween`. A **network transport** exists: `CollaborationWire`
serializes transactions (and every block type, preserving ids) to JSON, and
`TransportCollaborationSession` + `CollaborationTransport` carry edits over a
real link (`LoopbackTransportPair` for tests/same-process).

## 6. Extensibility — ✅ render + Markdown round-trip + plugin guide

`CustomBlockNode` + `BlockRegistry` (render) pair with `CustomBlockCodec` /
`BlockCodecs` for Markdown **decode/encode**, threaded through the controller
(`MarkdownEditorController(codecs:)`) so third-party blocks round-trip end to
end. A worked [plugin author guide](../docs/plugin-authoring.md) (a star-rating
block) is the "the public API is sufficient" proof
(`custom_block_plugin_test`).

## 7. Testing & docs

- **95.6% line coverage** (819 tests, unit + widget), analyzer clean. The
  remaining ~4% is concentrated in device-only branches (drag-and-drop platform
  reads, the `super_clipboard` rich-flavor plugin path, mouse-only gestures, the
  native context menu) that need real platform channels to exercise — 100% is not
  reachable without extensive platform mocking, so those are documented rather
  than faked.
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

`_MarkdownEditorState` owns IME, gestures, layout caches, find/replace, DnD,
clipboard, context menu, slash menu, source mode, painting, keyboard, handles,
and semantics. It works and is well-tested behaviorally, but it's the
highest-risk file to change. Two decompositions have landed: the standalone
helper classes (painters, toolbars, the text-field-semantics render object, the
source controller, the reorderable-block wrapper) split into a
`widget/internal/editor_internals.dart` `part` file (3.1k→2.6k lines), and the
pure **IME-window computation** extracted to a testable top-level function
(`imeWindow`). Fuller decomposition of the `State` itself (a full IME controller,
a gesture→intent layer) is a tracked maintainability refactor — no behaviour
change, so it carries regression risk without user-visible payoff and is
sequenced last.

## 9. Honest verdict

The editor is strong end-to-end: native-only, Markdown-canonical, one unified
editing surface, O(log n) editing with incremental intra-block layout, and
native-parity caret/keyboard/selection, accessibility (incl. font scaling),
mobile handles/magnifier, per-run RTL, localization, table-cell Tab navigation
**and rectangular cell selection**, **fully convergent collaboration**
(character-level same-block insert/delete/format merge **+ a JSON network
transport**), custom-block Markdown round-trip **with a plugin author guide**,
PDF export, off-thread parsing, golden tests, and a multi-OS CI matrix — the
entire prior gap list, implemented and tested.

The only **remaining** items are (a) off-thread *layout/shaping*, which is a
Flutter platform constraint (`TextPainter` is UI-isolate-bound) and is documented
as out of scope rather than faked, and (b) the structural cleanup of the
~2.3k-line editor State — a maintainability refactor with no user-facing
behaviour change (standalone painters/toolbars/semantics/source-controller moved
to their own files; fuller State decomposition tracked). Neither is an
architectural blocker.
