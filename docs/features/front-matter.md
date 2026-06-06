# Front matter

YAML front matter at the very start of a document (between `---` fences) is preserved verbatim
and shown as a labelled card; it round-trips unchanged.

```markdown
---
title: My Post
tags: [flutter, markdown]
---

The body starts here.
```

A `---` that isn't at the document start is a normal horizontal rule.
