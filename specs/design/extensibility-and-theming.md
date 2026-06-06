# 09 — Extensibility, Theming & Public API (L7)

Guiding principle: **everything is a plugin.** Built-in blocks, inline marks, input rules,
shortcuts, toolbar/slash items, and Markdown codecs all use the *same* public API a third
party uses. If a core feature needs a private hook, that's a design smell.

## 09.1 The public API surface

`lib/markey_mark.dart` exports only the supported surface:

```dart
// Widget + controller
class MarkdownEditor extends StatefulWidget { /* ... */ }
class MarkdownEditorController extends ChangeNotifier {
  MarkdownEditorController({String? markdown});
  String get markdown;                 // serialize model -> markdown (source of truth)
  set markdown(String value);          // parse -> model (replaces content)
  Document get document;               // read-only model access
  DocumentSelection? get selection;
  EditorMode get mode;                 // wysiwyg | source
  void toggleMode();
  void execute(EditRequest request);   // programmatic edits (same path as UI)
  void undo(); void redo();
  Stream<EditEvent> get events;        // observe changes (e.g., autosave)
}

enum EditorMode { wysiwyg, source }
```

`MarkdownEditor` constructor (sketch):

```dart
MarkdownEditor({
  required MarkdownEditorController controller,
  EditorStyle? style,                  // theming; defaults from ThemeData
  List<EditorPlugin> plugins = const [],   // additive extensions
  List<ToolbarItem>? toolbarItems,     // null = sensible defaults
  List<SlashMenuItem>? slashItems,
  bool readOnly = false,
  bool showToolbar = true,
  EditorMode initialMode = EditorMode.wysiwyg,
  FocusNode? focusNode,
  ScrollController? scrollController,
  ValueChanged<String>? onChanged,     // convenience: markdown on every change
  ImageUploadHandler? onInsertImage,   // host hook for paste/drag image upload
  DiagramRenderer? diagramRenderer,    // Mermaid provider (default: source card)
  MathRenderer? mathRenderer,          // default: flutter_math_fork
  CodeHighlighter? codeHighlighter,    // default: re_highlight
  ClipboardBridge? clipboard,          // default: super_clipboard
});
```

Everything under `lib/src/` is private; we never ask consumers to import `src`.

## 09.2 The plugin contract

A plugin bundles everything a feature needs so it can be added in one line:

```dart
abstract class EditorPlugin {
  List<NodeSpec> get nodes;            // node type + parser + serializer + component
  List<InlineMarkSpec> get inlineMarks;// attribute + parser + serializer + style
  List<InputRule> get inputRules;
  Map<ShortcutActivator, Intent> get shortcuts;
  List<EditAction> get actions;        // Intent -> EditRequest handlers
  List<ToolbarItem> get toolbarItems;
  List<SlashMenuItem> get slashItems;
  List<EditReaction> get reactions;
}

class NodeSpec {
  final String type;
  final BlockParser parser;            // markdown AST -> node
  final NodeSerializer serializer;     // node -> markdown
  final BlockComponent component;      // node -> widget (+ geometry)
}
```

Adding, e.g., a "callout" block is: define a `CalloutNode`, a `BlockParser` (recognize the
Markdown form, e.g. `> [!note]`), a `NodeSerializer`, a `BlockComponent`, optional input
rule / slash item — wrap in an `EditorPlugin`, pass to `MarkdownEditor(plugins: [...])`. **No
core changes.** This is the acceptance test for "extensible by design" (success criterion #4
in [01-vision-and-scope.md](./vision-and-scope.md)).

The built-in feature set is itself implemented as a `CorePlugin` registered first, proving
the API is sufficient.

## 09.3 Registries

Plugins populate central registries the layers consult:

- `BlockComponentRegistry` (type → component) — rendering
- `BlockParserRegistry` (priority-ordered) — markdown→model
- `NodeSerializerRegistry` (type → serializer) — model→markdown
- `InlineMarkRegistry` (attribute → parse/serialize/style)
- `InputRuleRegistry` (ordered)
- `ShortcutRegistry` / `ActionRegistry`
- `ToolbarRegistry` / `SlashMenuRegistry`
- `ReactionRegistry`

Order matters for parsers/rules; registries accept a priority and plugins can override
built-ins by registering higher priority (with a guardrail that warns on conflicts).

## 09.4 Theming: `EditorStyle`

```dart
class EditorStyle {
  final TextStyle? baseTextStyle;
  final Map<int, TextStyle>? headingStyles;     // level -> style
  final TextStyle? codeTextStyle;
  final BoxDecoration? codeBlockDecoration;
  final BoxDecoration? quoteDecoration;
  final TableStyle? tableStyle;
  final Color? selectionColor;
  final Color? caretColor;
  final EdgeInsets? blockSpacing;
  final SlashMenuStyle? slashMenuStyle;
  final ToolbarStyle? toolbarStyle;
  // ...
  factory EditorStyle.fromTheme(ThemeData theme);   // sensible defaults from host theme
}
```

- Defaults derive from the host app's `ThemeData` (headless philosophy) so the editor looks
  native immediately; every field is overridable.
- Exposed as a `ThemeExtension` so it can live in the app theme and respond to light/dark.

## 09.5 Host hooks

- `ImageUploadHandler` — called on image paste/drop/insert; returns a URL (or data URI) the
  image node stores. Default: keep as in-memory/data URI.
- `LinkResolver` / `onTapLink` — control link rendering/opening.
- `DiagramRenderer`, `MathRenderer`, `CodeHighlighter`, `ClipboardBridge` — swappable
  providers (defaults provided; can be stubbed for tests / strict dependency policies).
- `autosave` via the `events` stream or `onChanged`.

## 09.6 Stability & versioning

- Public API changes follow semver; `src/` is free to change.
- A documented "plugin author guide" (in `example/`) demonstrates a custom block end-to-end.
- We keep the `CorePlugin` honest: if building a core feature tempts a private hook, we
  promote that hook to the public API instead.
