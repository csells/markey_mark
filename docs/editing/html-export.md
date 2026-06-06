# HTML export

The editor can serialize the current document to semantic, self-contained HTML
— useful for publishing, email, or feeding another renderer.

```dart
final html = controller.toHtml();
```

You can also convert any document or Markdown string directly:

```dart
final html = Markdown.toHtml(document);   // from a Document
final html2 = '# Hello'.markdownToHtml(); // from a Markdown string
```

## What it produces

The encoder is pure Dart — **no JavaScript** — so the export works on every
platform. The mapping:

| Source | HTML |
| --- | --- |
| Headings | `<h1>`…`<h6>` |
| Paragraphs | `<p>` |
| Bold / italic / strikethrough | `<strong>` / `<em>` / `<del>` |
| Inline code / code blocks | `<code>` / `<pre><code class="language-…">` |
| Links | `<a href="…">` |
| Bulleted / numbered lists | `<ul>` / `<ol>` (nested by indent) |
| Task lists | `<ul class="task-list">` with disabled `<input type="checkbox">` |
| Block quotes | `<blockquote>` |
| Tables | `<table>` with per-column `text-align` |
| Images | `<img src alt title>` |
| Horizontal rules | `<hr>` |
| Definition lists | `<dl><dt><dd>` |
| Footnotes | `<sup><a href="#fn-…">` references + `<div class="footnote">` |
| Math | `<span class="math">` / `<div class="math math-display">` (LaTeX preserved) |
| Mermaid | `<pre class="mermaid">` (source preserved) |

All text is HTML-escaped. Math and Mermaid keep their source so a downstream
step (or your own CSS/renderer) can style them; nothing is rendered with a
browser engine inside the editor.
