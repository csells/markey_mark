# 14 — Caret, Selection & Input (toward the best editor on any platform)

> Status: **caret/selection motor adopted & implemented** (§14.3–§14.5).
> Accessibility, mobile handles/magnifier, and bidi are **designed here with the
> concrete Flutter types to reuse** (§14.6–§14.8) and tracked as the next steps.

## 14.1 The debt we took on

markey_mark hand-paints every editing surface (`CustomPaint` + `TextPainter`, a
custom `DeltaTextInputClient`) instead of building on `EditableText`. That bought
the unified document-text stream, the O(log n) document, and per-line code
layout — but it took on the debt of **reimplementing everything `EditableText`
gives a single field for free**: vertical caret motion, word/line/doc movement,
keyboard selection, accessibility semantics, mobile selection handles, the
magnifier, and bidirectional text. This chapter pays that debt down, reusing
Flutter framework types wherever they are public, and is explicit about what is
done vs. designed.

## 14.2 What we learned (Flutter framework + super_editor)

**Flutter `RenderEditable` / `DefaultTextEditingShortcuts`:**
- Vertical movement uses a `VerticalCaretMovementRun` that stores a **goal x**
  (`_currentOffset`) and walks lines via `computeLineMetrics()`/baselines. The
  run is invalidated (goal column reset) on **horizontal motion, any selection
  change, any edit, layout change, or click**.
- ~28 `Intent`s in `text_editing_intents.dart` (the `DirectionalCaretMovementIntent`
  family carries `forward` + `collapseSelection`). Plain arrow ⇒
  `collapseSelection: true`; shift ⇒ `false`.
- Collapse-vs-extend: a **plain** arrow over a *range* collapses to the
  directional edge (`min` for backward, `max` for forward); **shift** keeps
  `baseOffset` fixed and moves only `extentOffset`.
- Word/line boundaries come from `TextLayoutMetrics.getWordBoundary` /
  `getLineAtOffset` (visual line, soft-wrap aware; spaces are their own word).
- Platform key maps differ: macOS uses Cmd (line/doc) + Opt (word); Windows/
  Linux use Home/End (line) + Ctrl (word/doc).

**super_editor (the closest architecture to ours):** the winning pattern is
**"component answers geometry per node; the document orchestrates cross-node
movement."** Each node's component implements `movePositionUp/Down/Left/Right`,
`getOffsetForPosition`, and `getEndPositionNearX`/`getBeginningPositionNearX`.
Vertical movement across nodes is: *ask the current component to move up/down;
if it returns null, take the caret's **x**, find the adjacent selectable node,
and ask it for the position nearest that x.* One `DocumentImeInputClient`
bridges all nodes to a single IME by serializing only the selected node(s).

## 14.3 The motor (implemented) — `CaretMotor`

`lib/src/editing/caret_motor.dart` is a **pure, layout-independent** motor over
the document model. It answers: *what is the caret position one
[CaretGranularity] step in a direction from here?*

```dart
enum CaretGranularity { character, word, lineBoundary, documentBoundary }

class CaretMotor {
  const CaretMotor(this.document);
  DocumentPosition? move(DocumentPosition from,
      {required bool forward, required CaretGranularity granularity});
  (DocumentPosition, DocumentPosition)? wordRangeAt(DocumentPosition pos);
  (DocumentPosition, DocumentPosition)? lineRangeAt(DocumentPosition pos);
}
```

- **character** uses grapheme-cluster boundaries (emoji/ZWJ families move as one).
- **word** uses editor semantics (skip whitespace, then a run of one class —
  word chars or punctuation), matching Flutter's word-wise move.
- **lineBoundary** is the *logical* line: the whole block for a paragraph, the
  **physical line** for a code block (between `\n`s), the cell text for a table
  cell. (Visual-line Home/End on wrapped paragraphs is a later refinement that
  needs layout; see §14.5.)
- **documentBoundary** jumps to the first/last editable block.
- Crossing a block edge moves to the next/previous **editable** block (skipping
  atomic blocks like images); **table cells are self-contained** — movement
  clamps within the cell (cross-cell Tab navigation is separate).

Everything here is layout-free, so it is exhaustively unit-tested
(`caret_motor_test.dart`) with zero widget dependency — the bulk of the
behavior, provable in milliseconds.

## 14.4 One selection authority — `controller.moveSelection`

```dart
void moveSelection({required bool forward,
    required CaretGranularity granularity, bool extend = false});
```

Implements Flutter's collapse-vs-extend exactly: a plain character move over a
range collapses to the directional edge; otherwise the motor computes the new
extent and we either keep the anchor (`extend`) or collapse to a caret.
`selectWordAt` / `selectLineAt` wrap the motor's ranges for click-selection.
This is the single entry point gestures, the keyboard, and the IME share, over
the same `DocumentText` global-offset coordinate system as §13.

## 14.5 Vertical movement with a goal column (implemented)

Vertical motion is the one movement that needs paint geometry, so it lives in
the widget (`_moveCaretVertical`) using the cached `TextPainter` (paragraphs) and
`CodeLayout` (code) — exactly super_editor's recipe:

1. Read the caret's block-local pixel offset + height (`_caretLocalGeometry`).
2. The **goal column** is that x, captured on the first vertical step and held
   in `_verticalGoalX` across a run; it **resets on any non-vertical caret
   change** (mirroring `VerticalCaretMovementRun.isValid`), enforced in
   `_onControllerChanged`.
3. Probe one line above/below at the goal x within the block; if it leaves the
   block, find the adjacent editable block and ask it for the position nearest
   the goal x at its top/bottom edge (`_positionNearXInBlock`, laying out an
   off-screen neighbour on demand at the last painted width).

Gated by `keyboard_navigation_test.dart`: up/down across blocks preserves the
column; the goal column **survives passing through a short line**; vertical
movement works inside a multi-line code block; shift+up/down extends across
blocks. Key bindings (`_caretShortcuts`) are platform-aware (macOS Cmd/Opt vs.
Home/End + Ctrl elsewhere), each with a shift-to-extend variant; Alt/Opt+Up/Down
remains the markey_mark block-reorder affordance.

**Remaining motor refinement:** visual-line (soft-wrap) Home/End and within-block
up/down currently rely on `TextPainter.getPositionForOffset` probing rather than
`computeLineMetrics()`; switching to line metrics would make wrapped-paragraph
Home/End land on the *visual* line start/end like Flutter. Tracked.

## 14.6 Accessibility (implemented) — reuse `SemanticsConfiguration`

A hand-painted editor is invisible to screen readers unless it declares text-field
semantics. The WYSIWYG surface is now wrapped in a `Semantics` node that reuses
Flutter's `SemanticsConfiguration` (read-side block labels/headers/image-alt
already came from the painted `Text`/`RichText`):

| Reuse (via the `Semantics` widget) | Provide |
| --- | --- |
| `textField: true`, `readOnly:`, `multiline: true` | declares an editable text field to TalkBack/VoiceOver/NVDA |
| `value:` | the active block's visible text (`_semanticsValue`) |
| `onSetSelection` (`SetSelectionHandler`) | maps the semantic `TextSelection` to a `DocumentSelection` in the active block |
| `onMoveCursorForward/BackwardByCharacter` | delegate to `controller.moveSelection` (the shared `CaretMotor`), honouring the `extendSelection` flag |

Gated by `accessibility_test.dart`: the editor reports `isSemantics(isTextField:
true, value: …, hasMoveCursorForwardByCharacterAction: true, …)`, read-only mode
reports `isReadOnly: true`, and performing the `moveCursorForwardByCharacter`
semantic action actually advances the document caret. The cursor-move semantics
reuse the motor, so there is one movement implementation behind keyboard, IME,
and assistive tech.

**Next a11y refinement:** the `Semantics` widget can't carry `textSelection`
(that lives on `SemanticsConfiguration` in a `RenderObject`); to expose the live
caret offset (so a screen reader announces caret position and supports
word-granularity cursor moves), wrap the surface in a small
`SingleChildRenderObjectWidget` whose render object sets
`config.textSelection` and `onMoveCursorForward/BackwardByWord`. Tracked.

## 14.7 Mobile handles, magnifier & toolbar (designed — next) — reuse Flutter overlays

All public and reusable by a custom editor that supplies its own geometry
(`package:flutter/widgets.dart` + `material.dart`):

| Reuse | Provide |
| --- | --- |
| `SelectionOverlay` | `selectionEndpoints` (global handle positions from our layouts), `lineHeightAtStart/End`, three `LayerLink`s, a `TextSelectionDelegate` |
| `MaterialTextSelectionControls` / `CupertinoTextSelectionControls` | a `TextSelectionDelegate` (copy/cut/paste/selectAll — we have these on the controller) |
| `AdaptiveTextSelectionToolbar(.editable)` via `contextMenuBuilder` | the selection rect + button callbacks (replaces the deprecated `buildToolbar`) |
| `TextMagnifierConfiguration` + `MagnifierInfo` + `MagnifierController` | during a drag, push `MagnifierInfo(globalGesturePosition, caretRect, fieldBounds, currentLineBoundaries)` (all derivable from our painters) |

We already compute caret rects and selection boxes (`_BlockPainter`,
`CodeLayout.getBoxesForSelection`), so the geometry inputs exist; the work is
wiring an overlay + drag handles on touch platforms. This directly repays the
"`EditableText` gives mobile handles for free" debt without giving up custom
rendering.

## 14.8 Bidirectional / RTL text (designed — later)

`TextDirection.ltr` is currently hardcoded. The path: thread a per-paragraph
`TextDirection` (auto-detected from first strong character, overridable) into
`TextPainter`/`CodeLayout`, drive caret affinity through `TextPosition.affinity`
(already on `TextNodePosition`), and let the motor consult visual order for
left/right at bidi boundaries. The model is ready (affinity exists); the layout
and motor need direction-awareness.

## 14.9 Coverage posture

New code ships with unit + UI tests as a hard rule: the motor is unit-tested
across every granularity, direction, block type, and edge (document/cell edges,
emoji clusters, atomic-block skipping); the keyboard wiring and goal-column
behavior are UI-tested through real key events. Accessibility, handles, and
magnifier (§14.6–§14.7) will land the same way — a failing semantics/overlay
test first, then the wiring.
