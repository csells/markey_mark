# 04 — Markdown Pipeline (L0)

Markdown is the **source of truth** (ADR-002). This layer converts Markdown text ⇄ document
model. There is no off-the-shelf Dart package that does a lossless round trip with a real
AST, so we **own the serializer** and the round-trip test corpus, and we adapt appflowy's
**two-level codec** design.

## 04.1 Parser: Markdown text → AST

We use `dart-lang/markdown` (v7.3.x, actively maintained — it is the substrate
`flutter_markdown_plus`, `markdown_widget`, appflowy, and super_editor all build on) and
extend it with custom syntaxes.

```dart
final document = md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,   // tables, strikethrough, autolinks, fenced code
  blockSyntaxes: [
    MathBlockSyntax(),       // $$ ... $$   -> Element('math_block')
    FrontMatterSyntax(),     // --- ... --- at doc start -> Element('front_matter')
    // (mermaid needs NO custom syntax: it's a fenced code block w/ info string 'mermaid')
  ],
  inlineSyntaxes: [
    MathInlineSyntax(),      // $ ... $     -> Element('math')
  ],
)..enableTaskLists()         // GFM task list extension (not on by default)
 ..enableFootnotes();        // 7.1.0+
```

Custom syntax pattern (math example), the standard approach:

```dart
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'(?<!\$)\$([^$\n]+)\$(?!\$)');
  @override bool onMatch(md.InlineParser parser, Match m) {
    parser.addNode(md.Element.text('math', m[1]!));
    return true;
  }
}
```

**Known parser facts we design around:**
- The AST is **HTML-shaped** (`p`, `h1`, `strong`, `em`, `code`, `a`, `ul/ol/li`, `table`,
  `pre>code`) and **lossy** — no source spans, no original markers (`*` vs `_`, `-` vs `+`,
  fence type). We do not bind the model to it; we *map* it (§04.3).
- GFM coverage: tables ✅, strikethrough ✅, autolinks ✅, fenced code+lang ✅, task lists ✅
  (explicit enable), footnotes ✅ (7.1.0+). Definition lists ❌ → custom `BlockSyntax`.
- Mermaid is just a fenced code block whose info string is `mermaid`; we branch on the
  language in the mapper.

## 04.2 Optional fidelity: source hints

Because the AST discards surface markers, a pure model→Markdown serialize is **normalized**
(canonical), not byte-identical — and that is provably the best a normalizing AST can do
(per the CommonMark author). For users who care about preserving their exact style, we
optionally capture **source hints** per node at parse time:

```dart
class SourceHints {
  String? emphasisMarker;     // '*' or '_'
  String? strongMarker;       // '**' or '__'
  String? bulletMarker;       // '-', '*', '+'
  String? headingStyle;       // 'atx' | 'setext'
  String? codeFence;          // '```' or '~~~'  (+ fence length)
  String? linkStyle;          // 'inline' | 'reference' | 'collapsed' | 'shortcut'
  int?    orderedStart;       // first number of an ordered list
}
```

Two ways to obtain them:
1. **Re-scan the source span** for a node (we track byte offsets while pre-scanning lines),
   or
2. **Vendor `dart_markdown`** (the abandoned-but-position-aware fork) for nodes carrying
   `markers` + line/column/offset — its data is *exactly* the surface info we need. We treat
   this as an optional, vendored enhancement, not a hard dependency.

Hints are **advisory**: the serializer honors them when `MarkdownStyle.preserveSource` is on;
otherwise it uses configured canonical forms (§04.4). Editing a node that gains/loses
structure drops its now-meaningless hints.

## 04.3 AST → model mapping (two-level, adapted from appflowy)

**Block level** — a priority-ordered registry of parsers; first match wins:

```dart
abstract class BlockParser {
  int get priority;
  bool canParse(md.Node node);
  Node? parse(md.Node node, InlineMapper inline, BlockParserRegistry registry);
}
```

Built-in parsers: heading, paragraph, blockquote, bullet/ordered/task list, code block
(detect `language-mermaid` → `MermaidNode`; `math_block` → `MathBlockNode`), table, image,
hr, front-matter, footnote. Custom blocks register their own `BlockParser`.

**Inline level** — a `NodeVisitor` walks the inline subtree with an **attribute stack**,
emitting `Delta` ops (the appflowy `DeltaMarkdownDecoder` pattern):

```dart
class InlineMapper implements md.NodeVisitor {
  final _attrs = <Map<String,Object?>>[{}];           // stack
  final _delta = Delta();
  bool visitElementBefore(md.Element el) {             // push attribute
    switch (el.tag) {
      case 'strong': _push({'bold': true});
      case 'em':     _push({'italic': true});
      case 'del':    _push({'strike': true});
      case 'code':   _push({'code': true});
      case 'a':      _push({'link': el.attributes['href']});
      case 'math':   _delta.insert(el.textContent, {'math': el.textContent}); return false;
    }
    return true;
  }
  void visitText(md.Text t) => _delta.insert(t.text, _merged());
  void visitElementAfter(md.Element el) => _pop();
}
```

## 04.4 Model → Markdown serializer (we own this)

No Dart serializer exists, so we write one in the style of `remark-stringify` /
`prosemirror-markdown` / super_editor's `serializeDocumentToMarkdown`: per-node and
per-attribute rules, a deliberate escape policy, and configurable canonical forms.

```dart
class MarkdownSerializer {
  final MarkdownStyle style;                 // canonical-form config + preserveSource flag
  final Map<String, NodeSerializer> nodeSerializers;     // by node.type
  final List<InlineSerializer> inlineSerializers;        // by attribute
  String serialize(Document doc);
}

class MarkdownStyle {
  String emphasis = '*';      // '*' | '_'
  String strong   = '**';     // '**' | '__'
  String bullet   = '-';      // '-' | '*' | '+'
  String codeFence = '```';
  String headingStyle = 'atx';
  String linkStyle = 'inline';
  bool   preserveSource = false;   // honor SourceHints when available
  bool   tightLists = true;
  // escaping policy, hard-break style ('  ' vs '\\'), list indent width, ...
}
```

Per-node serializers handle block structure (heading `#`, list markers + indentation, quote
`>`, fenced code with language, table with alignment row, image `![alt](url "title")`, math
`$$`, mermaid as a `mermaid` fenced block, hr `---`). The inline serializer walks the `Delta`
and wraps runs with the right markers, applying the **escape policy** (backslash-escaping
`*_[]<` etc. only where needed) and choosing inline vs reference links per `style`/hints.

**Custom node types** register a `NodeSerializer` so extensions round-trip without touching
the core (the super_editor `customNodeSerializers` pattern).

## 04.5 The hard problems & how we control them

The surface decisions that break textual fidelity, and our handling:

| Problem | Default (canonical) | With `preserveSource` |
|---------|---------------------|------------------------|
| Emphasis char `*` vs `_` | `style.emphasis` | per-node hint |
| Strong `**` vs `__` | `style.strong` | per-node hint |
| Bullet `-`/`*`/`+` | `style.bullet` | per-node hint |
| Ordered start / `.` vs `)` | `1.` | per-node hint |
| Heading ATX vs Setext | `atx` | per-node hint |
| Code fence ` ``` ` vs `~~~` + length | ` ``` ` | per-node hint |
| Link inline vs reference | `inline` | per-node hint |
| Hard break (`  ` vs `\`) | two spaces | configurable |
| Blank lines / whitespace | normalized | normalized |
| Escaping `*_[]<` | minimal-needed policy | same |

We **accept** a normalized round trip as correct; the bar is **idempotence** (parse∘serialize
is a fixed point) and **AST-stability** (serialize∘parse yields an equal model), not byte
equality — exactly how remark and prosemirror-markdown define success.

## 04.6 Round-trip test corpus (correctness gate)

A first-class, growing corpus of `.md` fixtures under `test/corpus/` covering every GFM
construct + each extension, plus adversarial cases (nested emphasis `_a*b*c_`, mixed lists,
tables with alignment & inline marks, math next to text, escaped delimiters, footnotes,
front-matter). For each fixture we assert:

1. **Idempotence:** `serialize(parse(serialize(parse(md)))) == serialize(parse(md))`.
2. **AST-stability:** `model(parse(md)) ≅ model(parse(serialize(parse(md))))`.
3. **No data loss:** semantic content (text, marks, structure) is preserved.
4. **Golden text:** the canonical serialization is checked into a golden file so regressions
   are visible in diffs.

This corpus is the single most important defense of "Markdown is sacred" and is required to
stay green in CI (see [10-testing-ci-packaging.md](./testing-ci-packaging.md)).

## 04.7 Extension representations (Markdown ⇄ model)

| Feature | Markdown | Model node / attribute |
|---------|----------|------------------------|
| Inline math | `$x^2$` | `Delta` run w/ `{'math': 'x^2'}` |
| Block math | `$$ … $$` | `MathBlockNode(tex)` |
| Mermaid | ` ```mermaid … ``` ` | `MermaidNode(source)` |
| Task list | `- [x] item` | `TodoListItemNode(checked: true)` |
| Footnote | `text[^1]` / `[^1]: …` | inline ref attr + `FootnoteDefNode` |
| Front-matter | `--- … ---` (doc start) | `FrontMatterNode(yaml)` (pass-through) |
| Definition list (ext) | `term\n: def` | `DefinitionListNode` (custom syntax) |
| Table | GFM pipe table | `TableNode` (cells = `TextBlockNode`, column aligns) |
