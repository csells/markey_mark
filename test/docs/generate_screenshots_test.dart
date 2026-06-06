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

  testWidgets('math-inline', (t) async {
    await shoot(t, 'math-inline',
        r'The mass–energy equivalence is $E = mc^2$, and a circle is $A = \pi r^2$.');
  });

  testWidgets('table', (t) async {
    await shoot(t, 'table',
        '| Feature | Native? |\n| :-- | :-: |\n| Tables | yes |\n| Math | yes |\n| Code | yes |');
  });

  testWidgets('footnotes', (t) async {
    await shoot(t, 'footnotes',
        'Here is a statement with a note[^1].\n\n[^1]: The footnote text.');
  });

  testWidgets('mermaid-pie', (t) async {
    await shoot(t, 'mermaid-pie',
        '```mermaid\npie title Languages\n"Dart" : 70\n"YAML" : 20\n"Other" : 10\n```');
  });

  testWidgets('mermaid-sequence', (t) async {
    await shoot(t, 'mermaid-sequence',
        '```mermaid\nsequenceDiagram\nparticipant Alice\nparticipant Bob\nAlice->>Bob: Hello Bob\nBob-->>Alice: Hi Alice\n```');
  });

  testWidgets('mermaid-flowchart', (t) async {
    await shoot(t, 'mermaid-flowchart',
        '```mermaid\ngraph TD\nA[Start] --> B{Choice}\nB -->|yes| C[Do it]\nB -->|no| D[Skip]\n```',
        size: const Size(760, 420));
  });

  testWidgets('mermaid-class', (t) async {
    await shoot(t, 'mermaid-class',
        '```mermaid\nclassDiagram\nclass Animal {\n+String name\n+makeSound()\n}\nAnimal <|-- Dog\nAnimal <|-- Cat\n```',
        size: const Size(760, 360));
  });

  testWidgets('mermaid-gantt', (t) async {
    await shoot(t, 'mermaid-gantt',
        '```mermaid\ngantt\ntitle Roadmap\nsection Build\nSpec : 2024-01-01, 10d\nCode : 2024-01-11, 20d\nsection Ship\nRelease : 2024-02-01, 5d\n```',
        size: const Size(760, 320));
  });

  testWidgets('mermaid', (t) async {
    await shoot(t, 'mermaid',
        '```mermaid\nmindmap\n  root\n    a\n    b\n```');
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
  // KaTeX glyph fonts (bundled with flutter_math_fork) so math renders.
  await _loadKaTeXFonts();

  // Material icon glyphs for the toolbar (resolve the Flutter SDK root).
  final flutterRoot = _flutterRoot();
  await load('MaterialIcons', [
    if (flutterRoot != null)
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

/// Loads the KaTeX glyph fonts bundled with `flutter_math_fork`, grouped by
/// family (the filename prefix before `-`), so math renders in screenshots.
Future<void> _loadKaTeXFonts() async {
  final home = Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final base = Directory('$home/hosted/pub.dev');
  if (!base.existsSync()) return;
  final pkg = base
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.split('/').last.startsWith('flutter_math_fork-'))
      .toList();
  if (pkg.isEmpty) return;
  final fontsDir = Directory('${pkg.first.path}/lib/katex_fonts/fonts');
  if (!fontsDir.existsSync()) return;

  final byFamily = <String, List<String>>{};
  for (final f in fontsDir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.ttf')) continue;
    final name = f.path.split('/').last; // e.g. KaTeX_Main-Bold.ttf
    final family = name.split('-').first; // KaTeX_Main
    byFamily.putIfAbsent(family, () => []).add(f.path);
  }
  for (final entry in byFamily.entries) {
    // flutter_math_fork references its fonts with a package prefix.
    for (final family in [
      'packages/flutter_math_fork/${entry.key}',
      entry.key,
    ]) {
      final loader = FontLoader(family);
      for (final path in entry.value) {
        loader.addFont(
            Future.value(ByteData.view(File(path).readAsBytesSync().buffer)));
      }
      await loader.load();
    }
  }
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
