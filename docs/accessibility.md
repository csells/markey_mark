# Accessibility

The editor builds an explicit semantics tree so screen readers (TalkBack, VoiceOver) can read
and navigate the document:

- **Headings** expose the header role plus their text.
- **Paragraphs / list items / quotes** expose their text as the semantics label.
- **Images** expose the image role with the `alt` text as the label.

Because the content is custom-rendered, these semantics are added deliberately (a plain
`CustomPaint` exposes nothing by default). Honoring OS font scaling and right-to-left text are
part of the same effort — see the design spec's cross-platform and feature-feasibility notes.
