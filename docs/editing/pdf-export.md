# PDF export

Export the document to a PDF byte stream with a **pure-Dart** writer — no
WebView, no JavaScript, and no third-party dependency (it uses the PDF base-14
fonts, which need no embedding):

```dart
final bytes = Markdown.toPdf(controller.document); // Uint8List
await File('out.pdf').writeAsBytes(bytes);
```

The layout flows top-to-bottom with automatic pagination: headings are larger,
code is set in Courier, and lists/quotes keep their markers. For full visual
fidelity (exact fonts, colours, diagrams), render the editor to images and embed
those instead — the text exporter is the dependency-free default.

## Off-main-thread parsing

For very large documents, parse off the UI isolate so the first frame doesn't
jank:

```dart
final doc = await Markdown.parseAsync(markdown); // runs in a background isolate
controller.setDocument(doc);
```

`parseAsync` yields the same document as `Markdown.parse`. (Custom-block codecs
aren't supported off-thread because closures can't cross isolate boundaries —
use the synchronous `parse` when you need them.)
