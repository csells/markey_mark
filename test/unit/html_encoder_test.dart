import 'package:flutter_test/flutter_test.dart';
import 'package:markey_mark/markey_mark.dart';

String html(String markdown) =>
    const HtmlEncoder().convert(Markdown.parse(markdown));

void main() {
  group('HtmlEncoder', () {
    test('headings carry a slug id for in-page links', () {
      expect(html('# Title'), '<h1 id="title">Title</h1>');
      expect(html('### Three'), '<h3 id="three">Three</h3>');
    });

    test('heading slugs lowercase, strip punctuation and hyphenate spaces', () {
      expect(html('## Hello, World!'),
          '<h2 id="hello-world">Hello, World!</h2>');
    });

    test('duplicate heading slugs get a numeric suffix', () {
      expect(
        html('# Intro\n\n# Intro'),
        '<h1 id="intro">Intro</h1>\n<h1 id="intro-1">Intro</h1>',
      );
    });

    test('paragraph with inline marks', () {
      expect(html('a **b** _c_ ~~d~~'),
          '<p>a <strong>b</strong> <em>c</em> <del>d</del></p>');
    });

    test('inline code and links', () {
      expect(html('use `code` here'), '<p>use <code>code</code> here</p>');
      expect(html('[Dart](https://dart.dev)'),
          '<p><a href="https://dart.dev">Dart</a></p>');
    });

    test('escapes HTML-special characters in text', () {
      expect(html('a < b & c > d'), '<p>a &lt; b &amp; c &gt; d</p>');
    });

    test('bulleted list', () {
      expect(html('- one\n- two'),
          '<ul>\n<li>one</li>\n<li>two</li>\n</ul>');
    });

    test('numbered list', () {
      expect(html('1. one\n2. two'),
          '<ol>\n<li>one</li>\n<li>two</li>\n</ol>');
    });

    test('task list', () {
      expect(
        html('- [x] done\n- [ ] todo'),
        '<ul class="task-list">\n'
        '<li><input type="checkbox" checked disabled> done</li>\n'
        '<li><input type="checkbox" disabled> todo</li>\n'
        '</ul>',
      );
    });

    test('blockquote groups consecutive paragraphs', () {
      // A blank quote line separates paragraphs (two quote blocks).
      expect(html('> a\n>\n> b'),
          '<blockquote>\n<p>a</p>\n<p>b</p>\n</blockquote>');
    });

    test('fenced code block escapes and keeps language class', () {
      expect(html('```dart\nvar x = 1 < 2;\n```'),
          '<pre><code class="language-dart">var x = 1 &lt; 2;</code></pre>');
    });

    test('horizontal rule', () {
      expect(html('a\n\n---\n\nb'), '<p>a</p>\n<hr>\n<p>b</p>');
    });

    test('image', () {
      expect(html('![alt](pic.png "t")'),
          '<p><img src="pic.png" alt="alt" title="t"></p>');
    });

    test('table with alignment', () {
      expect(
        html('| a | b |\n| :--- | ---: |\n| 1 | 2 |'),
        '<table>\n'
        '<thead>\n<tr><th style="text-align: left">a</th>'
        '<th style="text-align: right">b</th></tr>\n</thead>\n'
        '<tbody>\n<tr><td style="text-align: left">1</td>'
        '<td style="text-align: right">2</td></tr>\n</tbody>\n'
        '</table>',
      );
    });

    test('full document joins blocks with newlines', () {
      expect(html('# T\n\npara'), '<h1 id="t">T</h1>\n<p>para</p>');
    });

    test('String.markdownToHtml extension', () {
      expect('# Hi'.markdownToHtml(), '<h1 id="hi">Hi</h1>');
    });

    test('controller.toHtml serializes the live document', () {
      final c = MarkdownEditorController(markdown: '# Title\n\n**bold**');
      expect(c.toHtml(), '<h1 id="title">Title</h1>\n<p><strong>bold</strong></p>');
      c.dispose();
    });
  });
}
