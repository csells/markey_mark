# Contributing docs

Documentation is part of "done": every feature ships with a user-facing page (and a
screenshot where it's visual) in the `docs/` folder.

## Structure

- `docs/` — Markdown pages (this site), organized into Features / Editing / Reference.
- `docs/images/` — screenshots, **generated** by a test that drives the real editor.
- `mkdocs.yml` — site navigation and theme (MkDocs Material).

## Regenerating screenshots

The screenshots are produced by a widget test that loads real fonts, pumps each feature
through the actual `MarkdownEditor`, and writes PNGs:

```sh
flutter test test/docs/generate_screenshots_test.dart
```

Add a new `testWidgets(...)` case there for each new visual feature.

## Building the site locally

```sh
pip install mkdocs-material
mkdocs serve     # preview at http://127.0.0.1:8000
mkdocs build     # output to ./site
```

## Publishing

`.github/workflows/docs.yml` builds the site with MkDocs and deploys it to GitHub Pages on
every push to `main` that touches `docs/` or `mkdocs.yml`. It is a **static build** — it
renders the committed `docs/` (screenshots included) and does **not** regenerate images. So a
screenshot is published exactly as committed; regenerate it (above) when the feature it shows
changes, and commit the new PNG. (`docs/ci/github-pages-docs.yml` is a reference copy of the
live workflow.)
