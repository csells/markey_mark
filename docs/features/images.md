# Images

Inline images via standard Markdown, rendered with a native `Image` widget (with an alt-text
fallback when a URL can't load).

## Markdown

```markdown
![alt text](https://example.com/picture.png "Optional title")
```

The `alt` text is used as the accessibility label and as the fallback shown if the image
fails to load.

## Inserting

- **Slash menu:** type `/` and choose *Image* to insert a placeholder (then set the URL in
  source mode).
- **API:** `controller.insertImage(url, alt: 'description')`.
