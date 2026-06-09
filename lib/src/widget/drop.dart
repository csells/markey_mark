import 'package:meta/meta.dart';

/// What a drag-and-drop payload item contains.
enum DropKind { text, image }

/// One item from a drag-and-drop drop: either Markdown/plain [text] to parse and
/// insert, or an [image] referenced by URL/path.
@immutable
class DroppedItem {
  const DroppedItem.text(this.value)
      : kind = DropKind.text,
        alt = null;

  const DroppedItem.image(this.value, {this.alt}) : kind = DropKind.image;

  final DropKind kind;

  /// For [DropKind.text]: the Markdown/plain text. For [DropKind.image]: the
  /// image URL or file path.
  final String value;

  /// Optional alt text for an image item.
  final String? alt;

  @override
  bool operator ==(Object other) =>
      other is DroppedItem &&
      other.kind == kind &&
      other.value == value &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(kind, value, alt);
}
