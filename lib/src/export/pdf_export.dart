import 'dart:typed_data';

import '../model/document.dart';
import '../model/node.dart';

/// Exports a [Document] to a **PDF** byte stream with a pure-Dart writer — no
/// WebView, no JavaScript, no third-party dependency (uses the PDF base-14
/// fonts Helvetica and Courier, which need no embedding). A simple top-to-bottom
/// text layout with automatic pagination; headings are larger, code is set in
/// Courier, lists/quotes get their markers.
class PdfExporter {
  const PdfExporter({
    this.pageWidth = 612, // US Letter, 72dpi
    this.pageHeight = 792,
    this.margin = 50,
  });

  final double pageWidth;
  final double pageHeight;
  final double margin;

  Uint8List export(Document doc) {
    final lines = _layout(doc);
    final pages = _paginate(lines);

    final objects = <String>[]; // object bodies, 1-indexed by position+1
    // 1: Catalog, 2: Pages, 3: Helvetica, 4: Courier, then page/content pairs.
    objects.add('<< /Type /Catalog /Pages 2 0 R >>');
    final pageObjNums = [for (var i = 0; i < pages.length; i++) 5 + 2 * i];
    objects.add('<< /Type /Pages /Kids [${pageObjNums.map((n) => '$n 0 R').join(' ')}] '
        '/Count ${pages.length} >>');
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>');

    for (var i = 0; i < pages.length; i++) {
      final contentNum = 6 + 2 * i;
      objects.add('<< /Type /Page /Parent 2 0 R '
          '/MediaBox [0 0 ${_n(pageWidth)} ${_n(pageHeight)}] '
          '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> '
          '/Contents $contentNum 0 R >>');
      final stream = _contentStream(pages[i]);
      objects.add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
    }

    return _assemble(objects);
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  List<_Line> _layout(Document doc) {
    final out = <_Line>[];
    final width = pageWidth - 2 * margin;
    for (final node in doc.nodes) {
      if (node is TextBlockNode) {
        final size = _sizeFor(node);
        final prefix = _prefixFor(node);
        final text = prefix + node.delta.toPlainText();
        for (final w in _wrap(text, size, width, mono: false)) {
          out.add(_Line(w, size, false));
        }
      } else if (node is CodeBlockNode) {
        for (final raw in node.code.split('\n')) {
          final wrapped = _wrap(raw, 11, width, mono: true);
          for (final w in (wrapped.isEmpty ? [''] : wrapped)) {
            out.add(_Line(w, 11, true));
          }
        }
      } else if (node is ImageNode) {
        out.add(_Line('[image: ${node.url}]', 12, false));
      } else {
        // Tables, math, mermaid, custom, etc.: a readable placeholder line.
        final label = node.type;
        out.add(_Line('[$label]', 12, false));
      }
      out.add(const _Line('', 6, false)); // inter-block spacing
    }
    return out;
  }

  double _sizeFor(TextBlockNode node) {
    if (node.type == BlockType.heading) {
      switch ((node.level ?? 1).clamp(1, 6)) {
        case 1:
          return 24;
        case 2:
          return 20;
        case 3:
          return 16;
        default:
          return 14;
      }
    }
    return 12;
  }

  String _prefixFor(TextBlockNode node) {
    switch (node.type) {
      case BlockType.bulletedListItem:
        return '• ';
      case BlockType.numberedListItem:
        return '${node.number ?? 1}. ';
      case BlockType.todoListItem:
        return node.checked == true ? '[x] ' : '[ ] ';
      case BlockType.quote:
        return '> ';
      default:
        return '';
    }
  }

  /// Greedy word-wrap to the page width using a coarse average glyph width.
  List<String> _wrap(String text, double size, double width, {required bool mono}) {
    if (text.isEmpty) return [''];
    final perChar = (mono ? 0.60 : 0.50) * size; // average advance
    final maxChars = (width / perChar).floor().clamp(8, 1000);
    final words = text.split(' ');
    final lines = <String>[];
    var cur = '';
    for (final word in words) {
      // Hard-break a single over-long word.
      var w = word;
      while (w.length > maxChars) {
        if (cur.isNotEmpty) {
          lines.add(cur);
          cur = '';
        }
        lines.add(w.substring(0, maxChars));
        w = w.substring(maxChars);
      }
      final candidate = cur.isEmpty ? w : '$cur $w';
      if (candidate.length > maxChars && cur.isNotEmpty) {
        lines.add(cur);
        cur = w;
      } else {
        cur = candidate;
      }
    }
    if (cur.isNotEmpty || lines.isEmpty) lines.add(cur);
    return lines;
  }

  List<List<_Placed>> _paginate(List<_Line> lines) {
    final pages = <List<_Placed>>[];
    var page = <_Placed>[];
    var y = pageHeight - margin;
    for (final line in lines) {
      final lh = line.size * 1.4;
      if (y - lh < margin && page.isNotEmpty) {
        pages.add(page);
        page = <_Placed>[];
        y = pageHeight - margin;
      }
      y -= lh;
      page.add(_Placed(line, margin, y));
    }
    pages.add(page); // always at least one page
    return pages;
  }

  String _contentStream(List<_Placed> placed) {
    final b = StringBuffer();
    for (final p in placed) {
      if (p.line.text.isEmpty) continue;
      final font = p.line.mono ? '/F2' : '/F1';
      b.writeln('BT $font ${_n(p.line.size)} Tf '
          '${_n(p.x)} ${_n(p.y)} Td (${_escape(p.line.text)}) Tj ET');
    }
    return b.toString();
  }

  // ── Assembly (objects + xref + trailer) ─────────────────────────────────

  Uint8List _assemble(List<String> objects) {
    final bytes = BytesBuilder();
    void write(String s) => bytes.add(_latin1(s));

    write('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objects.length; i++) {
      offsets.add(bytes.length);
      write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }
    final xrefOffset = bytes.length;
    final count = objects.length + 1;
    write('xref\n0 $count\n');
    write('0000000000 65535 f \n');
    for (final off in offsets) {
      write('${off.toString().padLeft(10, '0')} 00000 n \n');
    }
    write('trailer\n<< /Size $count /Root 1 0 R >>\n');
    write('startxref\n$xrefOffset\n%%EOF');
    return bytes.toBytes();
  }

  static String _escape(String s) {
    final b = StringBuffer();
    for (final cu in s.codeUnits) {
      // PDF strings: escape \ ( ) ; drop non-Latin-1 to '?'.
      if (cu == 0x5c) {
        b.write(r'\\');
      } else if (cu == 0x28) {
        b.write(r'\(');
      } else if (cu == 0x29) {
        b.write(r'\)');
      } else if (cu < 0x20 || cu > 0xff) {
        b.write('?');
      } else {
        b.writeCharCode(cu);
      }
    }
    return b.toString();
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static List<int> _latin1(String s) =>
      [for (final cu in s.codeUnits) cu <= 0xff ? cu : 0x3f];
}

class _Line {
  const _Line(this.text, this.size, this.mono);
  final String text;
  final double size;
  final bool mono;
}

class _Placed {
  const _Placed(this.line, this.x, this.y);
  final _Line line;
  final double x;
  final double y;
}
