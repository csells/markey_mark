# Plugin authoring — add a custom block

markey_mark's block set is **open**: you can add a brand-new block type without
forking the editor. A block needs two things, and both are public API:

1. **Markdown round-trip** — a `CustomBlockCodec` that decodes a fenced block to
   a `CustomBlockNode` and encodes it back.
2. **Rendering** — a `BlockRegistry` entry that draws the `CustomBlockNode`.

## Worked example: a star-rating block

A `rating` block written as a fenced block round-trips to data and renders as
stars:

````markdown
```rating
4
```
````

### 1. The codec (Markdown ⇄ model)

```dart
final codecs = BlockCodecs([
  CustomBlockCodec(
    blockType: 'rating',
    fence: 'rating',                       // the fenced info string
    decode: (content) => {'stars': int.parse(content.trim())},
    encode: (node) => '${node.data['stars']}',
  ),
]);
```

### 2. The renderer

```dart
final registry = BlockRegistry({
  'rating': (context, node, style) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          node.data['stars'] as int,
          (_) => const Icon(Icons.star),
        ),
      ),
});
```

### 3. Wire them up

Pass the codecs to the controller (so Markdown parses/serializes your block) and
the registry to the editor (so it renders):

```dart
final controller = MarkdownEditorController(markdown: source, codecs: codecs);

MarkdownEditor(
  controller: controller,
  blockRegistry: registry,
);
```

That's it — `controller.document` now contains a `CustomBlockNode`, the editor
draws it, and `controller.markdown` serializes it back to the same fenced block.
This end-to-end path is covered by `custom_block_plugin_test`, which doubles as
the "the public API is sufficient" proof.

## Notes

- `CustomBlockNode.data` is a plain `Map<String, Object?>` — keep values
  JSON-serializable so the block also survives the
  [collaboration wire](editing/collaboration.md).
- For a non-Markdown block (one you seed programmatically), skip the codec and
  insert a `CustomBlockNode` via `controller.setDocument(...)`; only the registry
  renderer is required.
- The same `data` map is what your renderer reads, so decode into the exact shape
  your widget wants.
