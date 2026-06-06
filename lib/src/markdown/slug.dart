/// GitHub-style heading slug: lowercased, punctuation stripped, runs of
/// whitespace collapsed to single hyphens. Used for HTML heading ids and the
/// in-document table of contents so their anchors agree.
String slugify(String text) {
  var s = text.toLowerCase();
  s = s.replaceAll(RegExp(r'[^\w\s-]'), '');
  s = s.trim().replaceAll(RegExp(r'\s+'), '-');
  return s;
}

/// Allocates unique heading slugs within one document, suffixing duplicates
/// (`intro`, `intro-1`, `intro-2`, …) like GitHub does.
class SlugAllocator {
  final Map<String, int> _counts = {};

  String allocate(String base) {
    final n = _counts[base] ?? 0;
    _counts[base] = n + 1;
    return n == 0 ? base : '$base-$n';
  }
}
