@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Golden (reference-image) regression tests for the rendered editor. They use
/// the default deterministic test font (identical glyph boxes), so the goldens
/// are portable across platforms and catch layout/structure regressions.
///
/// Regenerate references with:
///   flutter test --update-goldens test/golden/render_golden_test.dart
void main() {
  Future<void> shoot(WidgetTester tester, String markdown, String name) async {
    final c = MarkdownEditorController(markdown: markdown);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SizedBox(
            width: 400,
            height: 300,
            child: MarkdownEditor(
              controller: c,
              enableDrop: false,
              showToolbar: false,
              readOnly: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await expectLater(
      find.byType(MarkdownEditor),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('basic document golden', (tester) async {
    await shoot(tester, '# Heading\n\nA paragraph.\n\n- one\n- two', 'basic');
  });

  testWidgets('code + quote golden', (tester) async {
    await shoot(tester, '> A quote\n\n```\ncode line\n```', 'code_quote');
  });
}
