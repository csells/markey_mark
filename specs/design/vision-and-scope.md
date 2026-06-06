# 01 — Vision & Scope

## Vision

> Prove that Flutter can build the most full-featured WYSIWYG Markdown editor in the
> world — one that feels like Google Docs, is backed by Markdown, runs natively on every
> Flutter platform, and that developers can drop into any app and extend without limits.

`markey_mark` is a single embeddable Flutter widget that gives an app a complete,
production-grade rich-text editing experience whose underlying representation is always
clean Markdown. It is **not** a fork of an existing editor and **not** a WebView wrapper —
it is a natively-rendered editor we own top to bottom.

## Who it's for

1. **App developers** who want to embed a rich editor (notes apps, docs apps, CMS, chat
   composers, AI chat front-ends, knowledge bases) and need the content to be portable
   Markdown, on any platform Flutter supports.
2. **End users** of those apps, who expect a modern, fluid, Google-Docs/Notion-class
   editing experience — live formatting, slash menus, drag handles, smart paste — without
   ever seeing raw syntax unless they want to.
3. **Power users** who want to drop into raw Markdown source at any moment and edit the
   text directly.

## Core capabilities (the product)

- **Dual-mode editing.** Fluidly toggle between WYSIWYG (rich) and Source (raw Markdown)
  views over a single source of truth, preserving caret, selection, and scroll.
- **Live Markdown "magic."** Typing Markdown shortcuts transforms content in place
  (`# `→H1, `**bold**`, `- `→bullet, ` ``` `→code block, `> `→quote, `[]`→task, `---`→rule,
  tables, etc.), with single-step undo and backspace-to-revert.
- **Google-Docs feel.** Persistent formatting toolbar with live selection state; floating
  selection ("bubble") toolbar; slash (`/`) command menu; per-block hover handles for
  insert/drag/reorder; placeholder text; smart paste (rich→structured, plain, paste-as-text).
- **Full GitHub-Flavored Markdown + extensions:**
  - Headings (ATX) 1–6, paragraphs, hard/soft breaks
  - Bold, italic, strikethrough, inline code, links, autolinks
  - Bullet / ordered / **task** lists, nested
  - Block quotes (nested), horizontal rules
  - Fenced & indented code blocks with language + syntax highlighting
  - **Tables** (GFM) — fully editable: add/remove/resize rows & columns, per-column alignment
  - Images (local, network, pasted, drag-dropped)
  - **Math** — inline `$...$` and block `$$...$$` (KaTeX, native)
  - **Mermaid** diagrams (` ```mermaid `) — **rendered 100% natively in Dart** (no JS/WebView)
  - Footnotes, definition lists (extension), emoji shortcodes
  - Front-matter (YAML) pass-through
- **100% native, zero web/JS.** No WebView, no JavaScript, no web-hosted content runs inside
  the widget — every feature (text, math, code, tables, images, **and Mermaid**) is pure
  native Flutter, so the widget is self-contained, offline, and identical on every platform.
- **Cross-platform parity.** One codebase, consistent behavior on iOS, Android, Web,
  Windows, macOS, Linux — adapting input/selection/menus to each platform's conventions.
- **Extensible by design.** Host apps register custom block/inline node types, input rules,
  shortcuts, toolbar items, slash-menu items, and Markdown (de)serializers. Headless theming
  adopts the host app's `ThemeData`.
- **Accessible & international.** Screen-reader semantics, RTL/bidi, OS font scaling.

## Success criteria

The project succeeds when:

1. The `MarkdownEditor` widget compiles and runs on **all six** Flutter targets from one
   codebase.
2. Round-tripping a comprehensive GFM+extensions corpus through
   `parse → model → serialize → parse` is **AST-stable** (idempotent) and human-clean.
3. The "feel" bar is met: live input rules, cross-block selection, slash menu, toolbar with
   live state, and source toggle all work with correct caret/undo behavior.
4. A developer can add a brand-new block type (node + renderer + input rule + Markdown
   codec) **without modifying the core package** — only via the public plugin API.
5. The widget is publishable to pub.dev with an example app, docs, tests, and green CI.

## Scope boundaries (non-goals, at least initially)

- **Not a full word processor.** No page layout, columns, headers/footers, footnotes-as-
  margin-notes, or print pagination. (Markdown has no such concepts.)
- **Not a real-time collaboration product out of the box.** The architecture is
  operation/transaction-based to make CRDT/OT integration *possible* later (see roadmap),
  but multi-user sync, presence, and a transport layer are **not** in initial scope.
- **No mandatory backend.** Image upload and persistence are host-app concerns exposed via
  hooks; the editor ships with sensible local/in-memory defaults and never *requires* a
  server. (No server is used for Mermaid either — it renders natively, on-device.)
- **Not a Markdown *renderer* library.** Display-only rendering is a byproduct, not the
  product; if you only need to show Markdown, use `flutter_markdown_plus`/`markdown_widget`.
- **Native LaTeX fidelity is "KaTeX-class," not 100% LaTeX.** `flutter_math_fork` covers the
  vast majority; exotic LaTeX may differ. (We do **not** offer a WebView/MathJax fallback —
  no JS is allowed in the widget; KaTeX-class native rendering is the ceiling.)
- **Native Mermaid is built in stages by diagram type** (ADR-005). Diagram types our engine
  doesn't yet support degrade gracefully to a read-only source card — but rendering is always
  native Dart, never JS/WebView.
- **Arbitrary raw HTML/CSS is not fully rendered.** With no WebView/JS, we render a safe known
  HTML subset natively and show anything else verbatim (escaped/code) — never silently
  dropped. Full arbitrary HTML+CSS fidelity is out of scope. See
  [15-feature-feasibility-and-performance.md](./feature-feasibility-and-performance.md).
- **Spell-check is platform-limited.** First-party spell-check exists only on Android/iOS;
  elsewhere it's via an optional pluggable `SpellChecker`. Not a uniform native capability.

## Guiding principles

1. **Markdown is sacred.** Every visual element must correspond to valid Markdown. The model
   forbids states that can't be serialized.
2. **Never break a platform.** A feature that can't work on a platform degrades gracefully;
   it never crashes or no-ops silently.
3. **Own the hard parts, borrow the leaves.** Model, layout, selection, IME, serializer are
   ours. Math/code/clipboard are leaf dependencies we can swap.
4. **Everything is a plugin.** Built-in blocks use the same public extension API third
   parties use. If we need a private hook to build a core feature, that's a smell.
5. **Correctness of caret, selection, and undo above all.** These are the differentiators
   between a toy and a real editor, and where every editor bleeds time.
