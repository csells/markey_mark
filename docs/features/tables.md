# Tables

GitHub-flavored tables with per-column alignment, rendered natively.

![Table](../images/table.png)

## Markdown

```markdown
| Feature | Native? |
| :--     | :-:     |
| Tables  | yes     |
| Math    | yes     |
```

The alignment row (`:--`, `:-:`, `--:`) sets left / center / right alignment per column. Cells
support inline formatting (e.g. **bold**, `code`, [links](links.md)), and the table
round-trips to clean Markdown.
