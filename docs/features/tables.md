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

The alignment row (`:--`, `:-:`, `--:`) sets left / center / right alignment per column, and
the table round-trips to clean Markdown.

## Editing

Tables are **editable in place**: click any cell to edit it, and use the add-row / add-column
buttons beneath the table to grow it. Cells accept inline Markdown (e.g. `**bold**`, `[links](…)`), so formatting round-trips. Every edit is undoable and reflected in the Markdown.
