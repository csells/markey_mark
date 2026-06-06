@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Generates the screenshots embedded in `docs/`.
///
/// This is a documentation generator implemented as a widget test so it can
/// drive the real editor. Run it explicitly:
///
/// ```sh
/// flutter test test/docs/generate_screenshots_test.dart
/// ```
///
/// It loads real system fonts so the captured text is legible (the default
/// test font renders as boxes), pumps each feature through the real
/// [MarkdownEditor], and writes PNGs to `docs/images/`.
void main() {
  const outDir = 'docs/images';

  setUpAll(() async {
    await _loadFonts();
    Directory(outDir).createSync(recursive: true);
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    String markdown, {
    Size size = const Size(760, 360),
    bool focusFirst = false,
    String? typeAfterFocus,
  }) async {
    final controller = MarkdownEditorController(markdown: markdown);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          fontFamily: 'Roboto',
        ),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Material(
                  color: Colors.white,
                  child: MarkdownEditor(controller: controller),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (focusFirst) {
      await tester.tap(find.byKey(
          ValueKey('markey-block-${controller.document.nodes.first.id}')));
      await tester.pump();
    }
    if (typeAfterFocus != null) {
      tester.testTextInput.enterText(typeAfterFocus);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 50));

    await _capture(tester, boundaryKey, '$outDir/$name.png');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  }

  testWidgets('hero / overview', (t) async {
    await shoot(t, 'hero', '''
# Welcome to markey_mark

A native, cross-platform **WYSIWYG Markdown editor** for Flutter.

- Markdown is the _source of truth_
- Type `**bold**`, `# heading`, `- list` and watch it transform
- Switch between rich and `source` views anytime
''', size: const Size(760, 380));
  });

  testWidgets('headings', (t) async {
    await shoot(t, 'headings',
        '# Heading 1\n\n## Heading 2\n\n### Heading 3\n\nBody paragraph text.');
  });

  testWidgets('formatting', (t) async {
    await shoot(t, 'formatting',
        'Inline marks: **bold**, _italic_, ~~strikethrough~~, `inline code`, '
        'and a [link](https://example.com).');
  });

  testWidgets('lists', (t) async {
    await shoot(t, 'lists',
        '- First bullet\n- Second bullet\n\n1. First step\n2. Second step');
  });

  testWidgets('tasks', (t) async {
    await shoot(t, 'tasks', '- [x] Write the editor\n- [ ] Ship it\n- [ ] Profit');
  });

  testWidgets('quote', (t) async {
    await shoot(t, 'quote',
        '> "The best way to predict the future is to invent it."\n\nA paragraph.');
  });

  testWidgets('code-block', (t) async {
    await shoot(t, 'code-block',
        "```dart\nvoid main() {\n  print('hello'); // a comment\n  var x = 42;\n}\n```");
  });

  testWidgets('table', (t) async {
    await shoot(t, 'table',
        '| Feature | Native? |\n| :-- | :-: |\n| Tables | yes |\n| Math | yes |\n| Code | yes |');
  });

  testWidgets('mermaid', (t) async {
    await shoot(t, 'mermaid',
        '```mermaid\ngraph TD;\n  A[Start] --> B{Choice};\n  B --> C[Done];\n```');
  });

  testWidgets('math', (t) async {
    await shoot(t, 'math', r'Euler:' '\n\n' r'$$' '\n' r'e^{i\pi} + 1 = 0' '\n' r'$$');
  });

  testWidgets('source-mode', (t) async {
    final controller = MarkdownEditorController(
        markdown: '# Title\n\nWith **bold** and a `code` span.');
    final boundaryKey = GlobalKey();
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: SizedBox(
              width: 760,
              height: 300,
              child: Material(
                  color: Colors.white,
                  child: MarkdownEditor(controller: controller)),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.byKey(const Key('markey_toggle_mode')));
    await t.pump(const Duration(milliseconds: 50));
    await _capture(t, boundaryKey, '$outDir/source-mode.png');
    await t.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('slash-menu', (t) async {
    await shoot(t, 'slash-menu', '', focusFirst: true, typeAfterFocus: '/');
  });
}

/// Captures the [boundaryKey] subtree to a PNG. `toImage` needs real async, so
/// it runs inside [WidgetTester.runAsync].
Future<void> _capture(
    WidgetTester tester, GlobalKey boundaryKey, String path) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _loadFonts() async {
  const fontDir = '/usr/share/fonts/truetype';
  Future<ByteData?> read(String path) async {
    final f = File(path);
    if (!f.existsSync()) return null;
    return ByteData.view((await f.readAsBytes()).buffer);
  }

  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    var any = false;
    for (final p in paths) {
      final data = await read(p);
      if (data != null) {
        loader.addFont(Future.value(data));
        any = true;
      }
    }
    if (any) await loader.load();
  }

  await load('Roboto', [
    '$fontDir/liberation/LiberationSans-Regular.ttf',
    '$fontDir/liberation/LiberationSans-Bold.ttf',
    '$fontDir/liberation/LiberationSans-Italic.ttf',
    '$fontDir/liberation/LiberationSans-BoldItalic.ttf',
  ]);
  await load('monospace', [
    '$fontDir/liberation/LiberationMono-Regular.ttf',
    '$fontDir/liberation/LiberationMono-Bold.ttf',
  ]);
  // Material icon glyphs for the toolbar (resolve the Flutter SDK root).
  final flutterRoot = _flutterRoot();
  await load('MaterialIcons', [
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// Derives the Flutter SDK root from the running Dart executable
/// (`<root>/bin/cache/dart-sdk/bin/dart`) or `$FLUTTER_ROOT`.
String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  var dir = File(Platform.resolvedExecutable).parent;
  for (final part in ['bin', 'dart-sdk', 'cache', 'bin']) {
    if (dir.path.split(Platform.pathSeparator).last == part) {
      dir = dir.parent;
    }
  }
  return Directory('${dir.path}/bin/cache/artifacts/material_fonts').existsSync()
      ? dir.path
      : null;
}
