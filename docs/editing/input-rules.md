# Markdown input rules

The "magic" that makes markey_mark feel like a Markdown editor: as you type, Markdown
shortcuts transform in place. Each transform is a single undo step, and pressing
**Backspace** immediately after reverts it to the literal characters you typed.

## Block rules (start of a line)

| Type this | Becomes |
|-----------|---------|
| `# ␣` … `###### ␣` | [Heading](../features/headings.md) 1–6 |
| `- ␣`, `* ␣`, `+ ␣` | [Bulleted list](../features/lists.md) |
| `1. ␣` | [Numbered list](../features/lists.md) |
| `[] ␣`, `[x] ␣` | [Task list](../features/tasks.md) item |
| `> ␣` | [Block quote](../features/quotes.md) |
| `---`, `***`, `___` | Horizontal rule |

## Inline rules (on typing the closing delimiter)

| Type this | Becomes |
|-----------|---------|
| `**bold**` | **bold** |
| `_italic_` | *italic* |
| `~~strike~~` | ~~strikethrough~~ |
| `` `code` `` | `inline code` |

!!! tip
    Pressing **Backspace** right after a rule fires undoes just the transform (e.g. a heading
    becomes the literal `# ` again) — so the rules never get in your way.
