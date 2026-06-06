# Getting started

## Install

Add `markey_mark` to your `pubspec.yaml` dependencies, then `flutter pub get`.

## A complete example

```dart
import 'package:flutter/material.dart';
import 'package:markey_mark/markey_mark.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: EditorPage());
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final controller = MarkdownEditorController(
    markdown: '# Hello\n\nStart typing — try `# `, `- `, or `**bold**`.',
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('markey_mark')),
        body: MarkdownEditor(controller: controller),
      );
}
```

## Working with the content

The controller treats Markdown as the source of truth:

```dart
final md = controller.markdown;     // get the document as Markdown
controller.markdown = '# New doc';  // replace the document from Markdown
controller.toggleMode();            // switch WYSIWYG ⇄ source
controller.undo();                  // undo / redo
```

Listen for changes (e.g. autosave):

```dart
controller.addListener(() => save(controller.markdown));
```

## Next

- Learn the [Markdown input rules](editing/input-rules.md) that transform text as you type.
- Use the [slash command menu](editing/slash-menu.md) to insert any block.
- Drop into [source mode](editing/source-mode.md) to edit raw Markdown.
