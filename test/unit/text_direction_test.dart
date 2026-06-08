import 'package:flutter/painting.dart' show TextDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/src/render/bidi.dart';

/// First-strong-character base direction detection (Unicode UAX #9 style),
/// so RTL scripts (Arabic/Hebrew) render and align correctly. Layout-free and
/// fully unit-tested.
void main() {
  test('plain Latin text is LTR', () {
    expect(resolveBaseDirection('hello world'), TextDirection.ltr);
  });

  test('Arabic text is RTL', () {
    expect(resolveBaseDirection('مرحبا بالعالم'), TextDirection.rtl);
  });

  test('Hebrew text is RTL', () {
    expect(resolveBaseDirection('שלום עולם'), TextDirection.rtl);
  });

  test('base direction follows the FIRST strong character', () {
    // Leading neutral punctuation/digits/spaces are skipped.
    expect(resolveBaseDirection('  123 — مرحبا'), TextDirection.rtl);
    expect(resolveBaseDirection('"hello" مرحبا'), TextDirection.ltr);
  });

  test('text with no strong character defaults to LTR', () {
    expect(resolveBaseDirection('123 — !?'), TextDirection.ltr);
    expect(resolveBaseDirection(''), TextDirection.ltr);
  });

  test('a leading emoji (neutral) does not force a direction', () {
    expect(resolveBaseDirection('😀 مرحبا'), TextDirection.rtl);
    expect(resolveBaseDirection('😀 hello'), TextDirection.ltr);
  });
}
