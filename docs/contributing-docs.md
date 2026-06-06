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

The GitHub Actions workflow that builds and deploys the site to GitHub Pages is provided as a
template at `docs/ci/github-pages-docs.yml`. Copy it to `.github/workflows/docs.yml` in the
repo (it lives under `docs/` here because the bot that authors these changes can't create
workflow files directly). Once added, new features become published docs automatically.
