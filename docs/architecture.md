# Architecture

markey_mark is a from-scratch native editor: it reuses Flutter's text *painting* engine and
replaces the single-run text *editing* widgets with its own document model, command pipeline,
and IME client. Markdown is the canonical document, with an owned, configurable serializer.

The full design specification lives in the repository under
[`specs/design/`](https://github.com/csells/markey_mark/tree/main/specs/design), including:

- Architectural decision records (native, no WebView/JS)
- Document model, Markdown pipeline, rendering, input/IME
- Data-structures & algorithms, cross-ecosystem best practices
- Feature feasibility, performance & responsiveness budgets

This user documentation is generated from the same repository (see
[Contributing docs](contributing-docs.md)).
