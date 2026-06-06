# Document statistics

The controller can report live size metrics for the current document, suitable
for a status bar or word-count indicator.

```dart
final stats = controller.documentStats();
print('${stats.words} words, ${stats.characters} characters, ${stats.blocks} blocks');
```

`documentStats()` returns a `DocumentStats` with three fields:

| Field | Meaning |
| --- | --- |
| `words` | Whitespace-delimited words across every text-bearing block and table cell. |
| `characters` | Characters counted as grapheme clusters (so emoji and combining marks count as one). |
| `blocks` | Every top-level block, including non-text blocks like rules, images and diagrams. |

Text is tallied from paragraphs, headings, list items, quotes, definitions and
table cells. Non-text blocks (horizontal rules, images, math blocks, diagrams)
contribute to `blocks` but not to `words` or `characters`.

## Keeping a live counter

Recompute on every change by listening to the controller:

```dart
controller.addListener(() {
  final stats = controller.documentStats();
  setState(() => _wordCount = stats.words);
});
```
