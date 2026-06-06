import 'package:flutter/material.dart';
import 'package:markey_mark/markey_mark.dart';

void main() => runApp(const MarkeyMarkDemoApp());

class MarkeyMarkDemoApp extends StatelessWidget {
  const MarkeyMarkDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'markey_mark demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  late final MarkdownEditorController _controller;

  static const _seed = '''
# Welcome to markey_mark

A native, cross-platform **WYSIWYG Markdown editor** for Flutter.

Type Markdown shortcuts and watch them transform: try starting a line with
`# ` for a heading, or wrap text in `**bold**` or `_italic_`. Toggle the
toolbar's code button to see (and edit) the raw Markdown source — it is always
the source of truth.
''';

  @override
  void initState() {
    super.initState();
    _controller = MarkdownEditorController(markdown: _seed.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('markey_mark')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: MarkdownEditor(controller: _controller),
        ),
      ),
    );
  }
}
