# Accessibility

The editor builds an explicit semantics tree so screen readers (TalkBack, VoiceOver) can read
and navigate the document:

- **Headings** expose the header role plus their text.
- **Paragraphs / list items / quotes** expose their text as the semantics label.
- **Images** expose the image role with the `alt` text as the label.

## Editable text-field semantics

The whole editing surface is also exposed as an **editable text field** (reusing
Flutter's `SemanticsConfiguration`), so assistive tech treats it like a native
field with a movable caret:

- It reports `isTextField` (and `isReadOnly` in read-only mode) with the active
  block's text as its value and the live caret as the `textSelection`.
- It honours the OS cursor-movement and selection actions —
  `moveCursorForward/BackwardByCharacter`, `…ByWord`, and `setSelection` — all
  routed through the same caret motor the keyboard uses, so there is a single
  movement implementation behind keyboard, IME, and screen readers.

## Right-to-left text

Each paragraph's base direction is detected from its first strong character
(Unicode UAX #9), so Arabic/Hebrew paragraphs render and align right-to-left and
the arrow keys move the caret visually. Mixed LTR/RTL documents keep each block
in its own direction.

## Mobile

On touch platforms a non-collapsed selection shows draggable handles and a
magnifier loupe, reusing the platform's native selection-control visuals.

## OS font scaling (dynamic type)

The editor honours `MediaQuery.textScaler`, so the OS / accessibility font-size
setting enlarges (or shrinks) the rendered text and the caret/selection geometry
that follows it — across paragraphs, code blocks, and table cells. Changing the
scale invalidates the layout caches, so it takes effect immediately.

Because the content is custom-rendered, these semantics are added deliberately (a plain
`CustomPaint` exposes nothing by default). See the design spec's cross-platform and
feature-feasibility notes, and
the [architecture overview](architecture.md) for the full motor design.
