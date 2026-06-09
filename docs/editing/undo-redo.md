# Undo & redo

Every edit is an invertible operation, so undo/redo is exact. Rapid typing coalesces into a
single undo step, and structural edits (formatting, block changes, input-rule transforms) are
their own steps.

- **Toolbar:** the undo/redo buttons (enabled when there's history).
- **Keyboard:** <kbd>Ctrl/Cmd</kbd>+<kbd>Z</kbd> and <kbd>Ctrl/Cmd</kbd>+<kbd>Shift</kbd>+<kbd>Z</kbd>.
- **API:** `controller.undo()` / `controller.redo()` (`controller.canUndo` / `canRedo`).
