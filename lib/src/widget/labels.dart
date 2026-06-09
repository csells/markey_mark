import 'package:flutter/foundation.dart';

/// User-facing UI strings for [MarkdownEditor] chrome (toolbar tooltips,
/// find/replace, table controls, the formatting bubble). Defaults to English;
/// pass a localized instance (e.g. built from your `AppLocalizations`) to
/// translate the editor without forking it.
///
/// This is a value object rather than a `LocalizationsDelegate` so it works
/// whether or not the host app uses Flutter's localization machinery; it has
/// value equality so swapping an identical instance doesn't churn the UI.
@immutable
class MarkdownEditorLabels {
  const MarkdownEditorLabels({
    this.bold = 'Bold',
    this.italic = 'Italic',
    this.strikethrough = 'Strikethrough',
    this.highlight = 'Highlight',
    this.inlineCode = 'Inline code',
    this.heading1 = 'Heading 1',
    this.undo = 'Undo',
    this.redo = 'Redo',
    this.toggleSourceToMarkdown = 'Markdown source',
    this.toggleSourceToRich = 'Rich text',
    this.find = 'Find',
    this.replace = 'Replace',
    this.previousMatch = 'Previous',
    this.nextMatch = 'Next',
    this.replaceAll = 'All',
    this.close = 'Close',
    this.addRow = 'Add row',
    this.addColumn = 'Add column',
  });

  final String bold;
  final String italic;
  final String strikethrough;
  final String highlight;
  final String inlineCode;
  final String heading1;
  final String undo;
  final String redo;
  final String toggleSourceToMarkdown;
  final String toggleSourceToRich;
  final String find;
  final String replace;
  final String previousMatch;
  final String nextMatch;
  final String replaceAll;
  final String close;
  final String addRow;
  final String addColumn;

  static const MarkdownEditorLabels english = MarkdownEditorLabels();

  @override
  bool operator ==(Object other) =>
      other is MarkdownEditorLabels &&
      other.bold == bold &&
      other.italic == italic &&
      other.strikethrough == strikethrough &&
      other.highlight == highlight &&
      other.inlineCode == inlineCode &&
      other.heading1 == heading1 &&
      other.undo == undo &&
      other.redo == redo &&
      other.toggleSourceToMarkdown == toggleSourceToMarkdown &&
      other.toggleSourceToRich == toggleSourceToRich &&
      other.find == find &&
      other.replace == replace &&
      other.previousMatch == previousMatch &&
      other.nextMatch == nextMatch &&
      other.replaceAll == replaceAll &&
      other.close == close &&
      other.addRow == addRow &&
      other.addColumn == addColumn;

  @override
  int get hashCode => Object.hashAll([
        bold,
        italic,
        strikethrough,
        highlight,
        inlineCode,
        heading1,
        undo,
        redo,
        toggleSourceToMarkdown,
        toggleSourceToRich,
        find,
        replace,
        previousMatch,
        nextMatch,
        replaceAll,
        close,
        addRow,
        addColumn,
      ]);
}
