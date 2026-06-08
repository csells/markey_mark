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
- **Gap:** off-main-thread parse/layout (isolates) for huge initial loads is not
  done; viewport virtualization relies on `ListView` (fine, but no custom
  windowing for very wide horizontal content).

## 4. Editing feel — ✅ brought to native-field parity this cycle

- **Caret/selection motor**: character (grapheme), word, logical & **visual**
  line, document; vertical up/down with a preserved goal column; works across
  paragraphs, code blocks, and table cells. Shift-extend for every move. Word/
  line deletion. Platform-aware key bindings (macOS vs others).
- **Accessibility**: the surface is a semantic text field (`isTextField`, live
  `textSelection`, `setSelection` + per-character/per-word cursor actions) plus
  the read-side header/label/image roles.
- **Mobile**: draggable selection handles + magnifier, scroll-following.
- **RTL/bidi**: per-paragraph base direction; visual arrow movement in RTL.

### Remaining editing gaps
- **Mixed-bidi visual caret**: left/right flips on the block's *base* direction;
  a paragraph mixing LTR+RTL runs still moves logically inside the minority run.
- **OS font scaling / dynamic type**: `MediaQuery.textScaler` is **not** applied
  to `EditorStyle`; large-font accessibility settings are ignored. (Real gap.)
- **Localization delegate**: no `LocalizationsDelegate`; UI strings/tooltips are
  hard-coded English.
- **Toolbar**: the formatting bubble and the clipboard context menu coexist by
  design; not consolidated into one adaptive surface.
- **Rectangular cross-cell table selection** and **Tab-between-cells** navigation
  are not implemented (within-cell editing/selection is).

## 5. Collaboration — ⚠️ built but not wired end-to-end

`ot.dart` (transform/TP1) and `CollaborationSession` exist and are tested in
isolation, but the runtime `applyRemote` path applies remote transactions
**without transforming against in-flight local ops**, and there is no network
transport. Concurrent same-block edits are last-writer-wins, not convergent.
Fractional-index ordering for mergeable concurrent reorders is also still open.
*This is the single most over-represented area relative to its real integration.*

## 6. Extensibility — ⚠️ partial

`CustomBlockNode` + `BlockRegistry` give a **render** extension point, but custom
blocks have no decode/encode registration (Markdown round-trip for third-party
blocks). No published "plugin author guide" / `CorePlugin` proof yet.

## 7. Testing & docs

- **~94% line coverage** (unit + widget; ~4.75k/5.05k lines), analyzer clean.
  This cycle lifted the lowest files — `drop.dart` 0%→100%, `clipboard.dart`
  24%→~70%, `code_layout.dart` 76%→~90% (the non-`LineHighlighter` fallback),
  `position.dart` 85%→~98%, plus caret-motor edges and the `DocumentText` error
  path. Lowest remaining: `markdown_editor.dart` (~90% — the 2.3k-line widget's
  platform/DnD/`super_clipboard` and other device-only branches) and the native
  `super_clipboard` rich-flavor read/write (needs a real platform channel).
  *(Note: the `--coverage` run is slow/flaky under instrumentation on a few heavy
  widget tests; the plain suite is green and the new tests pass in isolation.)*
- **Docs**: per-feature Markdown in `docs/` + a screenshot generator
  (`test/docs/generate_screenshots_test.dart`) + MkDocs config; this cycle added
  the caret-motor/RTL/mobile/a11y docs.
- **Gaps**: no **golden** image tests (only screenshot *generation*; `alchemist`
  per-platform goldens from the roadmap are absent); CI has a docs/Pages workflow
  but no visible multi-OS test matrix or `pana`/publish dry-run; PDF export is
  not implemented (HTML export is).

## 8. The "god widget"

`_MarkdownEditorState` is ~2.3k lines and owns IME, gestures, layout caches,
find/replace, DnD, clipboard, context menu, slash menu, source mode, painting,
keyboard, handles, and semantics. It works and is well-tested behaviorally, but
it's the highest-risk file to change and the hardest to unit-test in isolation.
The motor/semantics extraction this cycle reduced its logic surface; further
extraction (an IME controller, a gesture→intent layer) is the main structural
debt remaining.

## 9. Honest verdict

The editor is genuinely strong end-to-end: native-only, Markdown-canonical, one
unified editing surface, O(log n) editing with incremental intra-block layout,
and — after this cycle — native-parity caret/keyboard/selection, accessibility,
mobile handles/magnifier, and RTL. The credible gaps to "best on **any**
platform" are: **OS font scaling**, **localization**, **collaboration actually
converging** (wire OT + a transport), **golden/per-platform visual tests + CI
matrix**, **custom-block encode/decode**, and **mixed-bidi visual caret**. None
are architectural blockers — the seams exist; they are scoped, tracked features.
