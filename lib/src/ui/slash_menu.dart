import 'package:flutter/material.dart';

import '../model/node.dart';
import '../widget/controller.dart';

/// A single entry in the slash (`/`) command menu.
class SlashMenuItem {
  const SlashMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.apply,
  });

  /// Stable id, used for the item's widget key (`markey_slash_item_<id>`).
  final String id;
  final String label;
  final IconData icon;

  /// Applies the command to the (already-cleared) active block.
  final void Function(MarkdownEditorController controller) apply;

  bool matches(String query) =>
      query.isEmpty || label.toLowerCase().contains(query.toLowerCase());
}

/// The built-in slash commands.
final List<SlashMenuItem> defaultSlashItems = [
  SlashMenuItem(
    id: 'heading1',
    label: 'Heading 1',
    icon: Icons.title,
    apply: (c) => c.setBlockType(BlockType.heading, level: 1),
  ),
  SlashMenuItem(
    id: 'heading2',
    label: 'Heading 2',
    icon: Icons.title,
    apply: (c) => c.setBlockType(BlockType.heading, level: 2),
  ),
  SlashMenuItem(
    id: 'heading3',
    label: 'Heading 3',
    icon: Icons.title,
    apply: (c) => c.setBlockType(BlockType.heading, level: 3),
  ),
  SlashMenuItem(
    id: 'bulleted',
    label: 'Bulleted list',
    icon: Icons.format_list_bulleted,
    apply: (c) => c.setBlockType(BlockType.bulletedListItem),
  ),
  SlashMenuItem(
    id: 'numbered',
    label: 'Numbered list',
    icon: Icons.format_list_numbered,
    apply: (c) => c.setBlockType(BlockType.numberedListItem),
  ),
  SlashMenuItem(
    id: 'task',
    label: 'Task list',
    icon: Icons.checklist,
    apply: (c) => c.setBlockType(BlockType.todoListItem),
  ),
  SlashMenuItem(
    id: 'quote',
    label: 'Quote',
    icon: Icons.format_quote,
    apply: (c) => c.setBlockType(BlockType.quote),
  ),
  SlashMenuItem(
    id: 'code',
    label: 'Code block',
    icon: Icons.code,
    apply: (c) => c.insertCodeBlock(),
  ),
  SlashMenuItem(
    id: 'divider',
    label: 'Divider',
    icon: Icons.horizontal_rule,
    apply: (c) => c.insertDivider(),
  ),
  SlashMenuItem(
    id: 'image',
    label: 'Image',
    icon: Icons.image,
    apply: (c) => c.insertImage('https://example.com/image.png', alt: 'image'),
  ),
];

/// The slash menu overlay widget.
class SlashMenu extends StatelessWidget {
  const SlashMenu({
    super.key,
    required this.items,
    required this.query,
    required this.onSelected,
  });

  final List<SlashMenuItem> items;
  final String query;
  final ValueChanged<SlashMenuItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final filtered = items.where((i) => i.matches(query)).toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 280),
        // A Column (eagerly built) inside a scroll view so every item exists in
        // the tree even when the list overflows and scrolls.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in filtered)
                ListTile(
                  key: Key('markey_slash_item_${item.id}'),
                  dense: true,
                  leading: Icon(item.icon, size: 20),
                  title: Text(item.label),
                  onTap: () => onSelected(item),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
