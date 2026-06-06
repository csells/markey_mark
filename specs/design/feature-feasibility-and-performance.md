# 15 — Feature Feasibility, Performance, Responsiveness & Resource Budgets

This document answers a specific question: **are there modern Markdown-editor features we
cannot implement in native Flutter, cross-platform, without compromising our WYSIWYG +
syntax-highlighting + source-editor goals?** — and then codifies the **performance,
responsiveness, and resource requirements** (and their tests) so those goals are enforced,
not aspirational.

## 15.A The honest answer — what can't be done natively without compromise

After surveying the whole editor/parser landscape (docs 12–14), the vast majority of modern
features **are** achievable in pure native Flutter on all six platforms. There are **five**
genuine compromise areas, all bounded and all degrading gracefully:

| # | Feature | Native cross-platform? | The compromise & our mitigation |
|---|---------|------------------------|----------------------------------|
| 1 | **Arbitrary embedded raw HTML/CSS** (GFM allows raw HTML blocks/inline) | ❌ not fully | Flutter has no HTML/CSS engine, and we forbid WebView/JS (ADR-001). We render a **safe known subset** (e.g. `<br>`, `<sub>`, `<sup>`, simple tables) natively and show anything else **verbatim as an escaped code span / fenced block** — never silently dropped (the "Markdown-faithful subset" policy, doc 14 §14.1(10)). True arbitrary HTML+CSS fidelity is impossible without a browser engine. |
| 2 | **100% LaTeX math fidelity** | ⚠️ KaTeX-class only | `flutter_math_fork` is a native KaTeX port covering the vast majority of math; exotic LaTeX (full macro packages, `\usepackage`, TikZ) won't render. No MathJax/WebView fallback (no JS allowed). Unsupported expressions degrade to a **monospace source card with an error badge**. |
| 3 | **Full mermaid.js diagram fidelity, day one** | ⚠️ built in stages | No production native Dart Mermaid renderer exists; we build our own native engine (doc 05 §05.9). It will lag mermaid.js (esp. flowchart edge-routing/clusters). Unsupported diagram **types** degrade to a **source card** — always native, never JS. |
| 4 | **System-grade spell-check / autocorrect / suggestions** | ⚠️ mobile only | Flutter's `SpellCheckConfiguration`/`DefaultSpellCheckService` is wired to the OS spell checker on **Android & iOS only**; desktop & web have **no first-party spell-check**. We expose spell-check where the platform provides it and offer an optional pluggable `SpellChecker` interface (host can supply a dictionary) elsewhere. Not a uniform native capability. |
| 5 | **Web text-input parity (IME/composition, native spellcheck underline, autofill)** | ⚠️ web caveats | Flutter web renders text input in-framework and has documented IME/composition/selection quirks; native browser spellcheck squiggles and some autofill aren't available to a custom editor. We test web paths explicitly and accept that web IME has rough edges Flutter itself is still improving. |

**Crucially, none of the compromise areas touch our core goals.** The features we committed to —
**WYSIWYG editing, syntax highlighting, and a CodeMirror-competitive source editor** — are
**fully achievable natively, cross-platform, with no compromise**:

| Goal / feature | Native, all 6 platforms, no compromise? |
|----------------|------------------------------------------|
| WYSIWYG rich editing (headings, lists, quotes, tables, inline marks, links, images) | ✅ |
| **Syntax highlighting** (code blocks + source view) via `re_highlight` | ✅ (pure Dart, freshest highlight.js grammars) |
| **Source-mode editor** (raw Markdown, monospace, highlight, line-aware) | ✅ |
| WYSIWYG ⇄ source toggle, caret/scroll preserved | ✅ |
| Live input rules ("# "→heading, `**bold**`, …) | ✅ |
| Inline + block math (common cases) | ✅ (`flutter_math_fork`) |
| Editable GFM tables | ✅ (custom native grid) |
| Images (network/memory; paste/drag) | ✅ (`super_clipboard`/`super_drag_and_drop`) |
| Slash menu, bubble toolbar, block handles, drag-reorder | ✅ |
| Undo/redo, find/replace, selection, clipboard | ✅ |
| Contextual marker reveal (Obsidian/Typora-style) | ✅ (decoration layer, doc 05 §05.7) |
| Responsive mobile layout, touch selection, magnifier, context menus | ✅ |
| Accessibility semantics, RTL/bidi, font scaling | ✅ (custom semantics tree) |
| Real-time collaboration | ✅ achievable (op-log → CRDT); transport is the only extra piece |

**Bottom line:** the only things we *can't* match are arbitrary HTML/CSS, 100% LaTeX, day-one
full-Mermaid, uniform spell-check, and web IME parity — each bounded, each degrading
gracefully, and **none of them compromise WYSIWYG, syntax highlighting, or the source editor.**

## 15.B Performance & latency requirements (perceived-instant)

Target: every interaction not gated on I/O is **perceived as instant**, on low-end mobile too.

| Budget | Target | Rationale |
|--------|--------|-----------|
| **Keystroke → glyph on screen** | ≤ 1 frame; **< 16 ms** (ideally < 8 ms on 120 Hz) | The edit pipeline (delta → op → normalize → reparse-block → relayout-block → paint) runs **synchronously within the frame**. Only the edited block re-shapes. |
| **Caret/selection move** | < 16 ms | Pure geometry from a cached `TextPainter`; no re-shape. |
| **Toolbar/format/undo** | < 16 ms | One transaction + one block relayout. |
| **Mode toggle (WYSIWYG⇄source)** | < 100 ms typical doc | Serialize/parse on the UI isolate for typical docs; large docs parse off-thread with a placeholder. |
| **Open/parse a large document (load/paste)** | off-thread; UI never blocks | `compute`/isolate for whole-document parse; show progressive/placeholder content. |
| **Scroll a 10k-block doc** | 60–120 fps, no jank | `SliverList`/`ListView.builder` virtualization; off-screen blocks never laid out. |
| **Idle CPU** | ~0% | **No periodic timers when idle.** Caret blink runs **only while focused** and stops on blur. |

**Mechanisms (doc 13 + implementation):**
- **Synchronous edit pipeline** within a frame (xi retrospective: avoid async for interactive edits).
- **Per-block text-layout cache** keyed by `(delta, width, styleVersion)` — a steady-state
  keystroke causes **one** layout (the edited block) and **zero** for the rest; caret blink
  repaints without re-shaping (`shouldRepaint` reuses the cached `TextPainter`).
- **Reparse only the edited block** (widen to adjacent blocks only on boundary edits).
- **Viewport virtualization** so cost is bounded by what's visible, not document size.
- **Off-thread** for whole-document parse, image decode, and Mermaid layout.
- **Prefix-sum→Fenwick block index** for O(log n) offset/pixel mapping at scale.

## 15.C Resource-usage requirements

- **No idle work:** zero running timers/animations when unfocused/idle (enforced by a test
  that `pumpAndSettle` completes on an unfocused editor).
- **Bounded memory:** per-block `TextPainter`s are cached and **disposed** on replace and on
  widget dispose; off-screen blocks aren't laid out; large single blocks may opt into a rope
  (escape hatch, doc 13 §13.1).
- **No leaks:** all controllers/notifiers/timers/connections disposed; tests run under the
  leak tracker and must not leave pending timers.
- **Minimal allocations on the hot path:** reuse cached layouts and spans; `StringBuffer` for
  batch concatenation; immutable deltas allow cheap `identical()` change checks.

## 15.D Responsive & mobile requirements

- **Adaptive chrome:** the toolbar **scrolls horizontally** on narrow widths (mobile) so it
  never overflows; the mode toggle stays pinned and reachable. Slash menu / bubble toolbar
  reposition within the viewport.
- **Touch ergonomics:** ≥ 44 px touch targets; long-press word-select + magnifier; drag
  handles; platform-adaptive context menus (`AdaptiveTextSelectionToolbar`).
- **Soft-keyboard handling:** the caret stays visible when the keyboard opens (resize/scroll);
  layout reflows on orientation change and keyboard show/hide.
- **Breakpoints:** compact (phone) vs. regular (tablet/desktop) layouts; spacing and font
  scaling honor `MediaQuery.textScalerOf`.
- **Input modality:** soft-keyboard/IME on mobile **and** hardware keyboard + shortcuts on
  desktop/web from the same widget.

## 15.E Test requirements (enforced)

These requirements are **tested**, not just documented (added to the 100% mandate, doc 10):

- **Resource — no idle timers:** an unfocused editor must `pumpAndSettle` (proves no periodic
  blink timer runs while idle). *(implemented)*
- **Scale — virtualization:** an 800-block document builds **far fewer** than 800 block widgets
  (proves `ListView.builder` virtualization). *(implemented)*
- **Responsiveness — no overflow:** the editor renders at a 320 px-wide (phone) viewport with
  **no overflow exception**, toggle still reachable. *(implemented)*
- **Perf — localized work:** editing one block leaves other blocks' content untouched and their
  cached layouts valid. *(implemented)*
- **Leaks:** every widget test unmounts and the suite leaves no pending timers. *(implemented)*
- **Latency (CI benchmark, P1):** a microbenchmark asserts a single keystroke transaction +
  edited-block relayout stays within a frame budget on the CI host (a regression guard, not an
  absolute device number).
- **Soft-keyboard / orientation (P1):** widget tests with simulated `viewInsets` (keyboard) and
  size changes assert the caret stays visible and no overflow.
- **Feature degradation (P1):** unsupported math/mermaid/HTML render their **source-card
  fallback** (never crash, never silently drop).

## 15.F Summary

There is **no modern feature that forces us to abandon native, cross-platform implementation
of our core goals.** The handful of true compromises (arbitrary HTML/CSS, 100% LaTeX,
day-one full Mermaid, uniform spell-check, web IME parity) are bounded, degrade gracefully to
native fallbacks, and **leave WYSIWYG, syntax highlighting, and the source editor fully
intact**. The performance, resource, and responsiveness budgets above are now first-class
requirements with tests guarding them.
