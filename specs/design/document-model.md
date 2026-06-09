# 03 — Document Model (L1)

The document model is the heart of the editor and the thing we most deliberately **own**.
It is designed so that (a) every representable state maps to valid Markdown, (b) inline rich
text is compact and queryable, (c) positions and selections can span blocks, and (d)
mutations are expressed as invertible operations for undo and (future) collaboration.

We adapt the **appflowy_editor** block-tree + `Delta` inline representation (clean,
Markdown-friendly, supports nesting/tables) and the **super_editor** position/selection
vocabulary (`DocumentPosition`/`NodePosition`, atomic-node positions), but the types are our
own.

## 03.1 Nodes

```dart
/// Base class for every node in the document tree.
abstract class Node extends ChangeNotifier {
  String get id;                       // stable unique id (nanoid-style)
  String get type;                     // 'paragraph','heading','bulleted_list',...
  Map<String, Object?> attributes;     // block-level attributes (level, language, ...)
  List<Node> get children;             // block children (lists, quotes, table cells)
  Node? get parent;

  /// Source-fidelity hints captured at parse time (optional; see markdown-pipeline).
  SourceHints? sourceHints;
}
```

Two broad kinds:

- **`TextBlockNode`** — a block whose primary content is a single line/paragraph of rich
  inline text, stored as a `Delta` (see §03.2). Examples: `paragraph`, `heading`,
  `bulleted_list_item`, `numbered_list_item`, `todo_list_item`, `quote` (each line), table
  cell. May also have block `children` (nested lists/quotes).
- **`LeafBlockNode` / atomic nodes** — blocks with no editable inline text run, addressed as
  a single atomic unit: `image`, `horizontal_rule`, `math_block`, `mermaid`, `code_block`
  (whose content is plain text, not a `Delta`), `table` (a structured container).

```dart
class TextBlockNode extends Node {
  Delta delta;                         // the rich inline content
}
class HeadingNode extends TextBlockNode { int get level => attributes['level'] as int; }
class CodeBlockNode extends Node { String code; String? language; }
class ImageNode extends Node { String url; String? alt; String? title; }
class MathBlockNode extends Node { String tex; }
class MermaidNode extends Node { String source; }
class TableNode extends Node { /* rows × cols of TextBlockNode cells + column aligns */ }
class HorizontalRuleNode extends Node {}
```

**Why a tree (not a flat list).** super_editor uses a flat node list, which makes nested
lists and tables awkward (the AppFlowy team called this out explicitly). We use a tree so
list nesting, nested quotes, and table cells are natural parent/child relationships.

**Why `Delta` for inline text (not a node-per-style tree).** Storing inline styles as a
node-per-run explodes the tree and complicates editing. A `Delta` keeps a run of text with
its attributes in one node — compact, easy to diff, and what appflowy and Quill use.

## 03.2 Inline content: `Delta`

A `Delta` is an ordered list of text operations describing a run of styled inline content.

```dart
class Delta {
  final List<TextInsert> ops;          // we only need 'insert' ops for a document model
}

class TextInsert {
  final String text;                   // the characters
  final Map<String, Object?> attributes; // {'bold':true,'italic':true,'code':true,
                                          //  'link':'https://...','strike':true,
                                          //  'math':r'$x^2$', ...}
}
```

- Inline marks are boolean/string attributes on a run: `bold`, `italic`, `strike`, `code`,
  `link` (href), and atomic inline objects like inline `math` and inline images are encoded
  as a single-character placeholder run carrying the payload in attributes (the appflowy
  pattern: structured data as JSON-able attributes).
- `Delta` supports the standard operations needed for editing: `insert`, `delete`, `format`
  over a range, `concat`, `slice`, and `compose` (apply one delta atop another). These power
  the inline parts of `Operation`s (§03.5).

## 03.3 Document

```dart
class Document {
  final List<Node> roots;              // top-level blocks in order
  Node? nodeById(String id);
  NodePath pathTo(String id);          // tree path for traversal/operations
}

class MutableDocument extends Document with ChangeNotifier {
  void insert(NodePath at, Node node);
  void delete(NodePath at);
  void move(NodePath from, NodePath to);
  void replace(NodePath at, Node node);
}
```

`NodePath` is a list of child indices from the root (à la appflowy `Path`), e.g. `[2,0,1]`.
Paths are used by `Operation`s so edits are location-addressable and invertible.

## 03.4 Positions & Selection

We follow super_editor's vocabulary because it generalizes cleanly to atomic nodes:

```dart
class DocumentPosition {
  final String nodeId;
  final NodePosition nodePosition;     // node-type-specific
}

abstract class NodePosition {}
class TextNodePosition extends NodePosition { final int offset; final TextAffinity affinity; }
/// For atomic nodes (image, hr, math_block): the caret is either just-before or just-after.
class UpstreamDownstreamNodePosition extends NodePosition { final bool upstream; }

class DocumentSelection {
  final DocumentPosition base;         // where the selection started
  final DocumentPosition extent;       // where the caret is now
  bool get isCollapsed => base == extent;
}
```

- A **collapsed** selection (`base == extent`) is the caret.
- A selection can span multiple nodes; the layout (L3) computes the union of per-node
  highlight rects between `base` and `extent` (§05).
- Atomic nodes select as a whole (the `UpstreamDownstreamNodePosition` lets the caret sit on
  either side so you can navigate past an image/rule).

## 03.5 Transactions, Operations, and Undo

All mutations flow through invertible operations grouped into transactions. We adapt
appflowy's `Operation`/`Transaction` model (clean, collaboration-ready) and super_editor's
command framing (good ergonomics for higher layers).

```dart
abstract class Operation {
  final NodePath path;
  Operation inverse();                 // for undo; every op must invert exactly
}
class InsertOperation extends Operation { final List<Node> nodes; }
class DeleteOperation extends Operation { final List<Node> nodes; } // stores removed for inverse
class UpdateOperation extends Operation { final Map<String,Object?> before, after; } // attrs
class UpdateTextOperation extends Operation { final Delta before, after; } // node delta change
class MoveOperation extends Operation { final NodePath from, to; }

class Transaction {
  final List<Operation> operations;
  final DocumentSelection? selectionBefore;
  final DocumentSelection? selectionAfter;
}
```

- `Editor.apply(Transaction)` applies each op, captures the new selection, pushes the
  inverse transaction onto the undo stack.
- **Undo/redo** = applying inverse / re-applying transactions. Selection is restored from
  `selectionBefore`/`selectionAfter` so undo feels right.
- **Grouping:** rapid typing coalesces into one undo unit (time + contiguity heuristic);
  an input-rule transform is always its own single unit (ADR-006); structural edits
  (insert table, paste) are their own units.

This operation log is the seam where **CRDT/OT** can be introduced later (roadmap): operations
are serializable and location-addressable, so a future transport can ship them between peers
without changing L1–L4.

> **Position mapping with bias (state of the art).** Each transaction also yields a
> `PositionMapping` (per affected block: old offset → new offset with an **association/bias**:
> −1 stays before inserted text, +1 moves past it — the ProseMirror `StepMap`/`assoc` idea).
> **All** position-bearing state — caret, selection base/extent, decorations, future collab
> cursors — is remapped through it rather than recomputed ad hoc. This is the single most
> common source of subtle caret/selection bugs in editors. See
> [14-cross-ecosystem-best-practices.md](./cross-ecosystem-best-practices.md) §14.1(2).

## 03.6 Invariants (enforced by the model)

The model rejects states that cannot be serialized to valid Markdown:

1. Every block node has a Markdown-serializable `type` registered in the serializer.
2. `Delta` attributes are limited to the known inline mark set (extensions register new ones
   *with* a serializer rule, or they're rejected).
3. List items live under a list container; table cells live under a table; etc. (structural
   schema, validated on `apply`).
4. No empty document — there is always at least one (possibly empty) paragraph, so the caret
   always has a home (Google-Docs behavior).
5. Adjacent text runs with identical attributes are merged (normalized) after every
   transaction, keeping `Delta`s canonical and round-trips stable.

> **Normalize to a fixed point (state of the art).** Invariants 1–5 are enforced by a
> normalizer that runs as an `EditReaction` **in a loop until stable** (the Lexical
> NodeTransforms / Slate `normalizeNode` pattern): merge adjacent equal-attribute runs, drop
> empty runs, coalesce adjacent same-type blocks, repair schema. The model is thus always
> canonical **before** it is rendered or serialized, so serialization is a pure function. See
> [14-cross-ecosystem-best-practices.md](./cross-ecosystem-best-practices.md) §14.1(4).

> Schema validation is the Flutter-side equivalent of ProseMirror's "reject invalid
> transactions" guarantee that the original research doc praised — it is what keeps Markdown
> fidelity airtight.
