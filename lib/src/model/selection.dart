import 'package:meta/meta.dart';

import 'position.dart';

/// A document selection defined by an anchor ([base]) and the moving end
/// ([extent]). A collapsed selection (`base == extent`) is the caret.
@immutable
final class DocumentSelection {
  const DocumentSelection({required this.base, required this.extent});

  const DocumentSelection.collapsed(DocumentPosition position)
      : base = position,
        extent = position;

  final DocumentPosition base;
  final DocumentPosition extent;

  bool get isCollapsed => base == extent;

  DocumentSelection collapseTo(DocumentPosition position) =>
      DocumentSelection.collapsed(position);

  DocumentSelection copyWith({DocumentPosition? base, DocumentPosition? extent}) =>
      DocumentSelection(base: base ?? this.base, extent: extent ?? this.extent);

  @override
  bool operator ==(Object other) =>
      other is DocumentSelection && other.base == base && other.extent == extent;

  @override
  int get hashCode => Object.hash(base, extent);

  @override
  String toString() => 'DocumentSelection($base -> $extent)';
}
