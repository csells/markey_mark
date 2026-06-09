# AGENTS.md

Canonical shared project guidance for Codex, Claude Code, and Gemini CLI. `CLAUDE.md` and
`GEMINI.md` import this file; keep tool-specific notes there only when they should not apply to
the other agents.

## What this is

`markey_mark` is a from-scratch, **fully native, cross-platform WYSIWYG Markdown editor** for
Flutter (iOS, Android, web, Windows, macOS, Linux). It reuses Flutter's text *painting* engine
but replaces the single-run text *editing* widgets with its own document model, command
pipeline, and IME client. **Markdown is the canonical document**, with an owned, configurable
serializer and a switchable WYSIWYG⇄source mode.

**Hard constraint:** no dependency may host web content or run JavaScript inside the widget.
`webview_flutter`, `flutter_inappwebview`, MathJax/`flutter_tex`, and any JS-interop renderer
are **disallowed**. Math renders via `flutter_math_fork` (KaTeX); Mermaid diagrams render via
an in-house native `CustomPainter` engine. Keep this constraint in mind for any new feature.

## Commands

```sh
flutter pub get
flutter analyze                              # must be clean; lints in analysis_options.yaml
flutter test                                 # unit + widget suite (~816 tests)
flutter test test/unit/editor_flow_test.dart # a single test file
flutter test --name "substring of test name" # a single test by name
flutter test --tags golden                   # golden image comparison (excluded from default run)
flutter test --tags screenshots              # regenerates docs images (excluded from default run)
flutter test --coverage                      # writes coverage/lcov.info
flutter test --platform chrome test/unit test/widget  # run the UI suite compiled to JS (web) — catches web-only bugs
dart format lib test                         # NOTE: not gated in CI (predates Dart 3.7 "tall" formatter)
```

Tests run on the Dart VM by default, which hides JavaScript-only bugs (e.g. `1 << 32`
wrapping to 0 on web). The `--platform chrome` run above compiles the suite to JS and runs it
in headless Chrome. Tests that need `dart:io` (pixel capture, corpus fixture loaders) are
tagged `@TestOn('vm')` so they're skipped in the browser.

Run the demo app from `example/`: `cd example && flutter run`.

The `screenshots` and `golden` test suites are tagged (see `dart_test.yaml`) and **excluded
from the normal `flutter test` run** — invoke them explicitly with `--tags`.

## Architecture

The editor is a stack of layers, each depending only on those below it. Source is curated
under `lib/src/` with a single public barrel at `lib/markey_mark.dart` (only exports the
supported API — add new public types there).

- **L0 Markdown pipeline** (`lib/src/markdown/`): `MarkdownDecoder` parses text → model using
  dart-lang `markdown` + custom syntaxes; `MarkdownEncoder`/`HtmlEncoder` serialize model →
  Markdown/HTML. `block_codecs.dart` registers per-block-type codecs. The round trip is
  designed to be **idempotent and AST-stable** — preserve this when touching the pipeline.
- **L1 Document model** (`lib/src/model/`): `Document` is an immutable block tree of `Node`s
  (`TextBlockNode`, `CodeBlockNode`, `TableNode`, `ImageNode`, `MathBlockNode`, `MermaidNode`,
  etc.). Inline styled text within a block is a `Delta` of `TextRun`s. Positions/selections:
  `DocumentPosition`, `NodePosition` variants, `DocumentSelection`. Block ordering uses
  `FractionalIndex` (`fractional_index.dart`) so inserts/moves don't renumber siblings.
- **L4 Editing** (`lib/src/editing/`): `Editor` (a `ChangeNotifier`) holds the current
  `document` + `selection` and applies `EditTransaction`s of `Operation`s. **Undo uses inverse
  operations, not snapshot-replay** — every op must produce a correct `inverse()`. Rapid
  `'typing'`-tagged transactions coalesce into one undo unit within a 600ms window. Also here:
  `EditCommands` (high-level edits), `CaretMotor` (grapheme-aware movement), input rules
  (`input_rules.dart`, ProseMirror-style), search, and collaboration (OT: `ot.dart`,
  `ot_session.dart`, `delta_ot.dart`, `wire.dart`, `collaboration.dart`).
- **L2/L3 Render & layout** (`lib/src/render/`): reuses Flutter `TextPainter`; `delta_text.dart`
  maps `Delta` → `TextSpan`; code highlighting, source highlighting, bidi, code layout,
  diagram rendering live here.
- **L5 Input / L6 Chrome / L7 Widget** (`lib/src/widget/`, `lib/src/ui/`, `lib/src/theme/`):
  `MarkdownEditor` widget + `MarkdownEditorController` (the main public entry point);
  custom `DeltaTextInputClient` IME (`ime_delta.dart`); clipboard (`clipboard.dart`, degrades
  from `super_clipboard` to `Clipboard`); drag & drop (`drop.dart`); `BlockRegistry` for
  custom block UI; `SlashMenu`; `EditorStyle` theming; `MarkdownEditorLabels` localization.

A keystroke's life: IME delta → input-rule match → `EditRequest`/`EditCommand` → `Editor`
applies a `Transaction` (records inverse for undo) → document notifies → affected block
rebuilds via `TextPainter` → IME re-synced. Model can be serialized to Markdown at any time
(source view, copy, `controller.markdown`).

### Public API surface (typical entry points)

```dart
final controller = MarkdownEditorController(markdown: '# Hello');
controller.markdown;          // serialize document → Markdown
controller.markdown = '...';  // parse Markdown → document
controller.toggleMode();      // WYSIWYG ⇄ source (EditorMode)
MarkdownEditor(controller: controller);
```

## Extensibility

Leaf dependencies are wrapped behind in-house interfaces (`CodeHighlighter`, `DiagramRenderer`,
`ClipboardBridge`) so they can be swapped or stubbed — important for tests and for hosts with
strict dependency policies. New diagram types follow the `lib/src/diagram/mermaid_*.dart`
pattern: a pure `parse*` function + a `*View` widget. Custom blocks go through `CustomBlockCodec`
+ `BlockRegistry`. See `docs/plugin-authoring.md`.

## Conventions

- Match the surrounding code's idiom and comment density. The codebase favors immutable model
  types, pure functions for parsing/serialization, and `ChangeNotifier` for editor/controller.
- The detailed design specs live in `specs/design/` (decision records, document model, pipeline,
  rendering, input/IME, performance budgets). User-facing docs in `docs/` are partly generated
  from the repo. Note that `specs/design/architecture.md` describes an *aspirational* module
  layout that differs in places from the actual `lib/src/` tree — trust the code.
- Tests are organized as `test/unit/`, `test/widget/`, `test/integration/`, `test/golden/`,
  `test/property/` (round-trip property tests), and `test/corpus/` (CommonMark/GFM spec
  fixtures). When adding a feature, add round-trip/corpus coverage alongside unit/widget tests.
- CI (`.github/workflows/ci.yml`; reference copy in `docs/ci/ci.yml`) is a single Ubuntu job:
  analyze, the full suite incl. goldens, the unit+widget suite **compiled to JS in headless
  Chrome** (`--platform chrome`) to catch web-only bugs, the example web build (no-JS-interop
  proof), and a pub publish dry-run. The Pages docs site publishes via `.github/workflows/docs.yml`.
