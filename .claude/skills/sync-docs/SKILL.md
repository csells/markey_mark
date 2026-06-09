---
name: sync-docs
description: >-
  Keep the markey_mark user docs in sync with the code whenever a user-facing
  feature is added, changed, removed, or renamed — a new or modified block type,
  input rule, slash-menu/toolbar command, export, diagram, keyboard shortcut, or
  public API in lib/. Use this PROACTIVELY in the markey_mark repo right after
  you implement such a change, even if the user only asked for code and never
  mentioned docs: here documentation is part of "done", so the feature's docs
  page, its committed screenshot (if visual), the README feature list, the
  lib/markey_mark.dart exports, the mkdocs nav, and specs/gap-analysis.md all
  have to move together. Trigger on things like "I added/implemented/changed
  <feature>", "ship it", "document this feature", or "make everything
  consistent" after a capability change. Do NOT use it when nothing user-facing
  changed: internal refactors or bug fixes with identical output, dependency
  bumps, new tests, CI/Pages setup, generating marketing/hero images, or editing
  or rewording an existing doc or spec on its own (a typo fix, a clearer
  architecture page, or refreshing a coverage number in specs/gap-analysis.md) —
  i.e., prose-only edits not driven by a feature change.
---

# Sync markey_mark docs with the code

In this repo, docs are not an afterthought — `docs/contributing-docs.md` states it
outright: *"Documentation is part of 'done': every feature ships with a user-facing
page (and a screenshot where it's visual)."* The docs site is built with
`mkdocs build --strict`, which **fails on a missing nav entry or a broken link**, so
half-done doc updates break the published site. This skill is the checklist that keeps
all the surfaces consistent.

## When a feature changes, sync these surfaces

Work through this list. Skip an item only when it genuinely doesn't apply (and say so),
because a silently-skipped surface is exactly what drifts.

1. **The docs page** — `docs/features/<topic>.md` (a content type the user writes) or
   `docs/editing/<topic>.md` (an editing capability or behavior). Match the structure of
   the existing pages (see "Page shape" below). For a **new** page you must also add it to
   the `nav:` in `mkdocs.yml` — `--strict` will fail the build otherwise.
2. **The screenshot** — if the feature is visual, add or update its case in
   `test/docs/generate_screenshots_test.dart` and regenerate the PNG (see "Screenshots").
   Embed it near the top of the page as `![Alt text](../images/<name>.png)`.
3. **The README feature list** — `README.md` has a `## Features (today)` bullet list that
   advertises the headline capabilities. Add a bullet when the feature is a notable
   user-facing addition; revise or remove one when behavior changes or goes away. Don't
   list every minor tweak here — this is the marketing surface, keep it high-signal.
4. **The public API barrel** — `lib/markey_mark.dart` is the curated public surface. If the
   change adds, renames, or removes public types (a new `Node` subtype, a parser, a widget,
   an option enum), update the relevant `export ... show ...;` line. The barrel intentionally
   exposes only the supported API, so an unexported new type is effectively private.
5. **The gap analysis** — `specs/gap-analysis.md` tracks feature coverage and status. If it
   references the area you changed (e.g. a feature was "planned" and is now shipped, or a
   coverage figure moved), update it so the spec doesn't contradict the code.

## Page shape

Existing pages follow a consistent, skimmable structure. Mirror it so the new page doesn't
look bolted on. Example (`docs/features/headings.md`):

```markdown
# Headings

Six heading levels, written as ATX Markdown (`#` … `######`).

![Headings](../images/headings.png)

## How to create one

- **Type it:** ... (link to [input rules](../editing/input-rules.md))
- **Toolbar:** ...
- **Slash menu:** ... (link to [slash menu](../editing/slash-menu.md))

## Markdown

```markdown
# Heading 1
```

Pressing **Backspace** immediately after the transform reverts it.
```

Conventions to keep:
- Lead with an H1 title and a one-sentence description of the feature.
- Put the screenshot right after the intro (`../images/<name>.png` — pages live one level
  below `docs/`, so the image path is `../images/`).
- Show the **Markdown** the feature produces — this package's whole thesis is that Markdown
  is the source of truth, so every page should make the round-trip concrete.
- Cross-link related pages with relative links (`../editing/slash-menu.md`). `--strict`
  validates these, so a typo'd link fails the build — that's a feature, lean on it.

## Screenshots

Screenshots are **generated**, never hand-captured. `test/docs/generate_screenshots_test.dart`
is a widget test (tagged `screenshots`) that loads real fonts, pumps each feature through the
actual `MarkdownEditor`, and writes `docs/images/<name>.png`. To add one, add a case using the
`shoot` helper:

```dart
Future<void> shoot(
  WidgetTester tester,
  String name,            // -> docs/images/<name>.png
  String markdown, {
  Size size = const Size(760, 360),
  bool focusFirst = false,        // tap the first block (e.g. to show a caret)
  String? typeAfterFocus,         // simulate typing, e.g. to capture an input rule mid-transform
}) async { ... }

testWidgets('callouts', (t) async {
  await shoot(t, 'callouts', '> [!NOTE]\n> Heads up — this is a callout.');
});
```

Then regenerate (this rewrites the PNGs on disk):

```sh
flutter test test/docs/generate_screenshots_test.dart
```

**Commit the regenerated PNG** — the committed image in `docs/images/` *is* what the published
site serves. The docs Pages workflow does a static `mkdocs build` from the committed files; it
does **not** regenerate screenshots. So regenerating here, when the feature changes, is the
only thing that keeps the site current — that's the whole reason this step exists. (These tests
are excluded from CI's normal run via the `screenshots` tag. Pixel bytes differ slightly across
OSes; for illustrative screenshots that's fine — don't chase sub-pixel diffs.)

## Verify before you call it done

Run these and make sure they're clean — they catch the three ways doc updates rot:

```sh
flutter test test/docs/generate_screenshots_test.dart   # screenshot case compiles & renders
mkdocs build --strict                                    # nav entry present, no broken links
flutter analyze                                          # the export/test edits are sound
```

If `mkdocs` isn't installed locally: `pip install mkdocs-material`. `--strict` is the
important flag — a plain `mkdocs build` would hide the missing-nav and broken-link errors
that the publish workflow enforces.

## Quick reference: where things live

- `docs/features/*.md`, `docs/editing/*.md` — the pages; `docs/index.md`, `getting-started.md`,
  and `docs/{architecture,accessibility,plugin-authoring,contributing-docs}.md` — reference.
- `mkdocs.yml` — site `nav:` (the canonical feature→page map) and theme.
- `docs/images/*.png` — generated screenshots.
- `test/docs/generate_screenshots_test.dart` — the screenshot generator.
- `README.md` (`## Features (today)`) — headline feature list.
- `lib/markey_mark.dart` — public API barrel.
- `specs/gap-analysis.md` — feature coverage/status.
