# 10 — Testing, CI & Packaging

Correctness of caret, selection, undo, and Markdown round-trip is the difference between a
toy and a real editor. Testing is therefore first-class and tiered.

## 10.0 Coverage mandate — 100%

**Hard gate.** Every piece of specced functionality that is implemented must be covered by
tests at all three levels — **unit** (pure-Dart logic), **widget/UI** (the rendered widget and
its interactions), and **integration** (end-to-end flows through the public API). We target
**100% line + branch coverage** of `lib/` and treat coverage regressions as build failures.

- Coverage is measured with `flutter test --coverage` (lcov) and enforced in CI; the
  threshold starts at 100% for shipped code and may only be lowered for an explicitly
  annotated, justified reason (e.g., a platform-only branch unreachable in the test host),
  documented inline with `// coverage:ignore-...` and a comment.
- "Implemented but untested" is not an allowed state. A feature is not "done" (§10.6) until
  its unit + widget + integration tests exist and pass.
- Each public API method, each `EditRequest`/command, each input rule, each Markdown
  construct (via the round-trip corpus), and each interactive behavior (typing, selection,
  toggle, undo/redo, source switch) has explicit tests.
- New behavior lands **with** its tests in the same change; new bugs land **with** a failing
  regression test first.

## 10.1 Test tiers

1. **Unit (pure Dart, cheap, run on Linux CI):**
   - `Delta` operations (insert/delete/format/compose/slice) and normalization.
   - `Operation.inverse()` correctness (apply then inverse == identity) for every op.
   - Document schema invariants (§03.6).
   - Markdown parser custom syntaxes (math, mermaid detection, front-matter, footnotes).
   - **Markdown round-trip corpus** (§04.6) — the headline correctness gate.
2. **Widget tests:**
   - Input rules (type `# `→heading; `**x**`→bold; backspace-reverts-rule; single undo).
   - Selection across blocks; delete across boundaries (merge/split).
   - Caret movement (goal-x across wrapped lines and between blocks/atomic nodes).
   - Toolbar live state; slash menu open/filter/select/dismiss + keystroke-gating.
   - Source toggle preserves caret/selection/scroll.
   - Clipboard flavors (copy writes markdown/html/plain; smart paste branches).
   - IME deltas → document mutations (simulated `TextEditingDelta`s), composing region.
3. **Golden tests (rendering):** per block type and representative documents — paragraphs,
   headings, lists (nested), quotes, code (highlighted), tables (aligned), math (inline +
   block), images, selection highlight, caret. Goldens are **platform-sensitive**.
4. **Integration (example app):** drive the demo with `integration_test` on each platform for
   smoke coverage (load doc, type, format, toggle mode, paste).

## 10.2 The round-trip corpus

`test/corpus/*.md` fixtures, each asserting idempotence, AST-stability, no-data-loss, and a
checked-in golden serialization (§04.6). Categories: basic GFM, nested lists, tables (with
alignment + inline marks), code fences (langs + mermaid), math (inline/block), links
(inline/reference), footnotes, front-matter, definition lists, and **adversarial** cases
(nested emphasis `_a*b*c_`, escaped delimiters, mixed bullets, hard breaks, tight/loose
lists, edge whitespace). New bugs → new fixtures (regression-locked).

## 10.3 Golden strategy across platforms

Goldens render slightly differently per OS (font hinting). We use **`alchemist`** to store
per-platform goldens (`goldens/ci|macos|linux|windows/...`), keep cheap unit/widget tests on
`ubuntu-latest`, and run goldens in a controlled environment to avoid false diffs.

## 10.4 CI (GitHub Actions)

A matrix that proves the cross-platform promise:

- `ubuntu-latest`: `flutter analyze`, `dart format --set-exit-if-changed`, full unit +
  widget tests, round-trip corpus, `flutter pub publish --dry-run`, `pana` score check.
- `macos-latest`: build example for macOS + iOS (build only / simulator smoke); goldens.
- `windows-latest`: build example for Windows; relevant tests.
- Web: `flutter build web` of the example; web-tagged widget tests (`chrome` platform).
- Coverage upload; fail the build if the corpus or analyzer regresses.

## 10.5 Packaging for pub.dev

- **Pure Dart/Flutter package** (no platform channels of our own; native needs delegated to
  `super_clipboard`/`super_drag_and_drop`), so **no federated plugin** is required. If a
  future feature needs our own native code, only *that* feature becomes a federated plugin.
- `lib/markey_mark.dart` is the only public import; implementation under `lib/src/`.
- Required for a strong pub score: dartdoc on all public API, an `example/` app (also the
  living docs + plugin-author guide), a thorough `README.md`, `CHANGELOG.md`, and a permissive
  license.
- `pana` / `flutter pub publish --dry-run` gated in CI.
- Asset bundling: math fonts (KaTeX via `flutter_math_fork`), any default Mermaid web assets
  only if the WebView provider is used (kept out of the core).

## 10.5b Performance, responsiveness & resource tests

Per doc [15-feature-feasibility-and-performance.md](./feature-feasibility-and-performance.md),
these are first-class and enforced:

- **No idle work:** an unfocused editor `pumpAndSettle`s (no periodic caret-blink timer runs
  while idle).
- **Virtualization/scale:** a large (≥800-block) document builds far fewer than N block
  widgets (`ListView.builder` virtualization).
- **Responsiveness:** the editor renders at a 320 px (phone) viewport with no overflow; the
  mode toggle stays reachable; soft-keyboard (`viewInsets`) and orientation changes keep the
  caret visible (P1).
- **Localized work:** editing one block leaves others' content/layout untouched (cache reuse).
- **Latency benchmark (P1):** a CI microbenchmark guards keystroke→relayout against a
  per-frame budget (regression guard).
- **No leaks:** every widget test unmounts; suite leaves no pending timers/connections.

## 10.6 Definition of done (per feature)

A feature is "done" when: it has unit/widget tests, goldens where it renders, a corpus entry
if it touches Markdown, docs on any public API, works (or degrades gracefully) on all six
platforms, and the example app demonstrates it.
