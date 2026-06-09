# 06 — Input, IME & Editing (L4/L5)

This is where every Flutter editor bleeds time, and where correctness matters most. We
implement our own IME client (no `EditableText`), a hardware-key shortcut map, gesture
handling, the input-rules engine, and clipboard/drag-drop — all routed through the editing
command pipeline.

## 06.1 The editing command pipeline (L4)

Adapted from super_editor's `Editor` framing over our operation model (§03.5):

```
EditRequest  ──►  Editor  ──►  EditCommand(s)  ──►  Transaction(Operations)  ──► Document
                    │                                      │
                    │                                      └─► UndoManager (inverse txn)
                    └─► EditReaction(s) ──► more EditCommands (normalization, etc.)
                                          └─► EditEvent(s) ──► listeners (toolbar, IME sync)
```

- **`EditRequest`** = intent ("insert text X at selection", "toggle bold", "split block",
  "indent list item", "insert table"). The only way to mutate the document.
- **`EditCommand`** = executes a request into concrete `Operation`s; may read current
  document+selection.
- **`EditReaction`** = runs after a command, can append commands. Built-ins: `Delta`
  normalization (merge adjacent equal runs), list renumbering, table shape repair,
  "ensure trailing paragraph," and **input rules** (§06.4) are modeled as a reaction on text
  insertions.
- **`EditEvent`** = emitted facts ("selection changed", "node N changed") consumed by the
  toolbar (live state), the IME sync, and host listeners.

Undo/redo, grouping, and selection restoration work as in §03.5.

## 06.2 IME: our `DeltaTextInputClient` (L5)

We connect to the platform IME directly and use the **delta model** so we learn precisely
what changed (essential for a multi-node document) rather than diffing whole strings.

```dart
class EditorImeClient with DeltaTextInputClient {
  TextInputConnection? _conn;
  void attach() {
    _conn = TextInput.attach(this, TextInputConfiguration(enableDeltaModel: true, ...));
  }
  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    for (final d in deltas) { _applyDelta(d); }   // -> EditRequests
  }
  // performAction, updateFloatingCursor, insertContent, performSelector, showToolbar,
  // insert/removeTextPlaceholder (scribble), connectionClosed, ...
}
```

**Document ⇄ IME-text serialization (the crux).** The OS keyboard thinks it edits a flat
string with one selection and one composing range, but our document is a tree of nodes. We
maintain a serialized "IME view" of the **active editing region** (typically the current
block, plus context) and a bidirectional offset map between that flat string and document
positions (super_editor's `ImeAttributedTextEditingController` + `TextDeltasDocumentEditor`
approach). Incoming deltas are translated through the map into `EditRequest`s; after the
document changes we push the new serialized region back via `_conn.setEditingState(...)`.

**Composing region.** The `composing` `TextRange` (IME composition for CJK etc.) is tracked
and rendered as an underline by the text layer.
**Critical pitfall (documented):** never programmatically reset the composing region from a
listener — Gboard will fight to restore it and create an infinite loop. We only set composing
state as a direct consequence of a delta, never speculatively.

**Platform divergence.** Delta semantics differ across IMEs (notably macOS vs Linux, and
web). We centralize per-platform quirks in the IME layer and cover them with platform-tagged
tests; higher layers stay platform-agnostic.

**Floating cursor / Scribble / Scribe.** iOS floating cursor (`updateFloatingCursor`),
iOS Scribble and Android Scribe handwriting (`insert/removeTextPlaceholder`, `showToolbar`),
and keyboard rich-content insertion (`insertContent`, e.g. GIFs) are handled in the client.

## 06.3 Hardware keys: Shortcuts / Actions / Intents (L5)

Desktop/web hardware keys use Flutter's `Shortcuts → Actions → Intents` triad so bindings are
declarative and host-remappable.

- Intents: `ToggleBoldIntent`, `ToggleItalicIntent`, `ToggleCodeIntent`, `InsertLinkIntent`,
  `SetHeadingIntent(level)`, `ToggleBlockquoteIntent`, `IndentIntent`/`OutdentIntent`,
  `ToggleSourceModeIntent`, plus standard editing intents (move/extend selection by
  char/word/line/document, delete by char/word, select-all).
- Platform key maps: `meta:true` on macOS, `control:true` elsewhere (via
  `defaultTargetPlatform`); we model our defaults on `DefaultTextEditingShortcuts`.
- Actions translate intents into `EditRequest`s; the whole editor is wrapped in a
  `Focus`/`FocusScope` so shortcuts fire only when focused.

Baseline shortcut set: `Cmd/Ctrl+B/I/U`, `Cmd/Ctrl+K` (link), `Cmd/Ctrl+Shift+V` (paste
plain), `Cmd/Ctrl+Z` / `Cmd/Ctrl+Shift+Z` (undo/redo), heading shortcuts, list indent
(`Tab`/`Shift+Tab`), and the source-toggle shortcut.

## 06.4 Input rules — the live Markdown "magic" (ADR-006)

An ordered list of rules matched on each text-insertion delta, scoped to the current block's
text-before-caret:

```dart
class InputRule {
  final RegExp pattern;           // anchored to end-of-text-before-caret ($)
  final bool inline;              // block-type rules vs inline-mark rules
  EditRequest? apply(RuleMatch m, EditorState state);  // null = no-op
}
```

- **Block rules** (textblock-type / wrapping): `^(#{1,6})\s$`→heading; `^[-*+]\s$`→bullet;
  `^\d+[.)]\s$`→ordered; `^>\s$`→quote; `^```$`→code block; `^(---|\*\*\*|___)$`→hr;
  `^\[[ xX]?\]\s$`→task item.
- **Inline rules** (mark): `**x**`→bold, `*x*`/`_x_`→italic, `~~x~~`→strike, `` `x` ``→code,
  `[text](url)`→link, `$x$`→inline math. The pattern fires when the **closing** delimiter is
  typed; delimiters are removed and the captured run gets the mark.
- **Single undo unit** per rule; **Backspace immediately after** a rule reverts to the typed
  text (we track the last applied rule + its range, like prosemirror-inputrules).
- Rules are gated to **real keystrokes** — not paste, programmatic insert, or undo/redo (so
  pasting `# x` doesn't suddenly become a heading; that's the slash-menu/paste path's job).

This is the appflowy "character shortcut events" idea generalized to a regex rules engine
modeled on prosemirror-inputrules.

## 06.5 Selection gestures (L5)

We manage selection in the model (not via `SelectableRegion`, which is read-only) and drive
it with gesture recognizers:

- **Mouse/trackpad (desktop/web):** click to place caret, drag to extend, double-click =
  word, triple-click = paragraph, shift-click = extend, hover for cursor + block handles.
- **Touch (mobile):** tap to place caret, long-press = word select + magnifier + handles,
  drag handles to adjust, drag selection.
- **Magnifier** via `TextMagnifierConfiguration` on mobile; **context menu** via
  `contextMenuBuilder` + `AdaptiveTextSelectionToolbar` so menus are platform-native (Material
  / Cupertino / desktop) with our custom items (e.g. "Turn into", "Copy as Markdown").

## 06.6 Clipboard & smart paste (L5)

Backed by `super_clipboard` (all 6 platforms; web reads via paste events) behind a
`ClipboardBridge` interface that degrades to Flutter's plain-text `Clipboard`.

- **Copy:** write **multiple flavors** — `text/plain` (the Markdown), `text/markdown`, and
  `text/html` (rendered) — so pasting into other apps is rich, and pasting back into us is
  lossless via the Markdown flavor.
- **Paste (smart):** prefer `text/markdown` (lossless) → else `text/html` (convert HTML→model
  via an HTML importer) → else `text/plain` (parse as Markdown so pasted Markdown becomes
  structured). Images on the clipboard are inserted as image nodes (host upload hook).
- **Paste as plain text** (`Cmd/Ctrl+Shift+V`): insert `text/plain` verbatim, no parsing.

## 06.7 Drag & drop (L5)

Backed by `super_drag_and_drop` (optional):
- **Drop into editor:** OS files (images → image nodes via upload hook; `.md`/text →
  inserted/parsed), and text drags.
- **Reorder blocks:** drag a block handle to move a node (a `MoveOperation`); a drop-indicator
  shows the target gap.

## 06.8 Correctness focus list

The features most likely to be subtly wrong, called out for extra test coverage:
1. Cross-block selection + delete (merging/splitting nodes at boundaries).
2. IME composing region across block edges and during input-rule transforms.
3. Backspace-reverts-input-rule and single-undo grouping.
4. Caret movement (goal-x) across wrapped lines and between blocks/atomic nodes.
5. Paste of mixed content (Markdown vs HTML vs plain) producing valid model + Markdown.
6. Platform IME divergence (macOS selectors, Linux/web deltas, Android rich content).
