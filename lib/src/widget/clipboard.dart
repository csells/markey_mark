import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:meta/meta.dart';
import 'package:super_clipboard/super_clipboard.dart' as sc;

/// Multi-flavor clipboard contents. Markdown is the source of truth; [html] is
/// provided so pasting into rich targets keeps formatting, and [plainText] for
/// plain targets.
@immutable
class ClipboardPayload {
  const ClipboardPayload({this.markdown, this.html, this.plainText});

  final String? markdown;
  final String? html;
  final String? plainText;

  bool get isEmpty =>
      (markdown == null || markdown!.isEmpty) &&
      (html == null || html!.isEmpty) &&
      (plainText == null || plainText!.isEmpty);

  @override
  bool operator ==(Object other) =>
      other is ClipboardPayload &&
      other.markdown == markdown &&
      other.html == html &&
      other.plainText == plainText;

  @override
  int get hashCode => Object.hash(markdown, html, plainText);
}

/// Seam over the system clipboard so the editor's copy/paste logic is testable
/// and the OS integration is pluggable. The default
/// ([SystemClipboardBridge]) uses Flutter's plain-text clipboard and works
/// everywhere; [SuperClipboardBridge] adds true multi-flavor OS clipboard
/// support via `super_clipboard` (native, no JavaScript).
abstract class ClipboardBridge {
  Future<void> write(ClipboardPayload payload);
  Future<ClipboardPayload?> read();
}

/// Plain-text-only bridge using Flutter's built-in clipboard. Writes the
/// Markdown (falling back to plain text) and reads it back as plain text.
class SystemClipboardBridge implements ClipboardBridge {
  const SystemClipboardBridge();

  @override
  Future<void> write(ClipboardPayload payload) async {
    final text = payload.markdown ?? payload.plainText ?? '';
    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<ClipboardPayload?> read() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null) return null;
    return ClipboardPayload(markdown: text, plainText: text);
  }
}

/// Rich, multi-flavor OS clipboard via `super_clipboard` (native; no WebView,
/// no JavaScript). Writes Markdown as the plain-text flavor (so it round-trips
/// into markey_mark and plain targets) plus an HTML flavor for rich targets.
class SuperClipboardBridge implements ClipboardBridge {
  const SuperClipboardBridge();

  @override
  Future<void> write(ClipboardPayload payload) async {
    final clipboard = sc.SystemClipboard.instance;
    if (clipboard == null) {
      // Platform without a system clipboard: degrade to plain text.
      return const SystemClipboardBridge().write(payload);
    }
    final item = sc.DataWriterItem();
    final md = payload.markdown ?? payload.plainText;
    if (md != null) item.add(sc.Formats.plainText(md));
    if (payload.html != null) item.add(sc.Formats.htmlText(payload.html!));
    await clipboard.write([item]);
  }

  @override
  Future<ClipboardPayload?> read() async {
    final clipboard = sc.SystemClipboard.instance;
    if (clipboard == null) return const SystemClipboardBridge().read();
    final reader = await clipboard.read();
    String? plain;
    if (reader.canProvide(sc.Formats.plainText)) {
      plain = await reader.readValue(sc.Formats.plainText);
    }
    String? html;
    if (reader.canProvide(sc.Formats.htmlText)) {
      html = await reader.readValue(sc.Formats.htmlText);
    }
    if (plain == null && html == null) return null;
    // The plain flavor carries our Markdown.
    return ClipboardPayload(markdown: plain, html: html, plainText: plain);
  }
}
