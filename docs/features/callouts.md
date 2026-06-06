# Callouts (alerts)

markey_mark supports GitHub-style alerts (also called callouts or admonitions).
Write a block quote whose first line is an alert marker:

````markdown
> [!NOTE]
> Useful information that users should know, even when skimming.

> [!TIP]
> Helpful advice for doing things better or more easily.

> [!IMPORTANT]
> Key information users need to know to achieve their goal.

> [!WARNING]
> Urgent info that needs immediate user attention to avoid problems.

> [!CAUTION]
> Advises about risks or negative outcomes of certain actions.
````

Each kind renders as a tinted box with a coloured left border, an icon and a
title:

| Marker | Title | Colour |
| --- | --- | --- |
| `[!NOTE]` | Note | blue |
| `[!TIP]` | Tip | green |
| `[!IMPORTANT]` | Important | purple |
| `[!WARNING]` | Warning | amber |
| `[!CAUTION]` | Caution | red |

The marker is parsed away (it isn't shown as text), and the callout kind is
preserved on round-trip back to Markdown. Callouts can span multiple
paragraphs — keep prefixing lines with `>`:

````markdown
> [!NOTE]
> First paragraph.
>
> Second paragraph in the same callout.
````

In [HTML export](../editing/html-export.md), a callout becomes
`<div class="callout callout-note">…</div>` so you can style it with CSS.
