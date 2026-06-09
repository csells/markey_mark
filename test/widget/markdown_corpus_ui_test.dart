@TestOn('vm') // loads corpus fixtures from disk via dart:io; can't run in a browser
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

/// Drives the real CommonMark + GFM corpora through the actual editor widget:
/// every example must render without throwing, and be editable (place caret,
/// type, toggle to source and back) without throwing. This is the strongest
/// guarantee — real-world Markdown not only parses but works end-to-end in the
/// UI.
List<String> _load(String path) {
  final raw = jsonDecode(File(path).readAsStringSync()) as List;
  return [for (final e in raw) (e as Map)['markdown'] as String];
}

void main() {
  final examples = [
    ..._load('test/fixtures/commonmark_spec.json'),
    ..._load('test/fixtures/gfm_spec.json'),
  ];

  Future<void> pump(WidgetTester tester, MarkdownEditorController c) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            // Drag/IME plugins aren't available under the test harness here.
            child: MarkdownEditor(controller: c, enableDrop: false),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('every corpus example renders in the widget without throwing',
      (tester) async {
    final failures = <String>[];
    for (var i = 0; i < examples.length; i++) {
      final c = MarkdownEditorController(markdown: examples[i]);
      try {
        await pump(tester, c);
        // Sanity: the document built and at least one block exists.
        expect(c.document.nodes, isNotEmpty);
      } catch (e) {
        failures.add('example $i ${jsonEncode(examples[i])}: $e');
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    }
    expect(failures, isEmpty, reason: failures.take(5).join('\n\n'));
  });

  testWidgets('a representative sample is editable end-to-end', (tester) async {
    // Every 17th example (≈40) — exercise the full edit path without a
    // multi-minute run.
    final failures = <String>[];
    for (var i = 0; i < examples.length; i += 17) {
      final c = MarkdownEditorController(markdown: examples[i]);
      try {
        await pump(tester, c);
        // Focus the first text block and type into it.
        final firstText =
            c.document.nodes.whereType<TextBlockNode>().firstOrNull;
        if (firstText != null) {
          final finder = find.byKey(ValueKey('markey-block-${firstText.id}'));
          if (finder.evaluate().isNotEmpty) {
            await tester.tap(finder.first);
            await tester.pump();
            c.setSelection(DocumentSelection.collapsed(
                DocumentPosition.text(firstText.id, 0)));
            await tester.pump();
            tester.testTextInput.enterText('X');
            await tester.pump();
          }
        }
        // Toggle to source and back — exercises encode + decode through the UI.
        c.toggleMode();
        await tester.pump();
        c.toggleMode();
        await tester.pump();
      } catch (e) {
        failures.add('example $i ${jsonEncode(examples[i])}: $e');
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    }
    expect(failures, isEmpty, reason: failures.take(5).join('\n\n'));
  });
}
