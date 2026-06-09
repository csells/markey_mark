# Find & replace

Press <kbd>Ctrl/Cmd</kbd>+<kbd>F</kbd> to open the find bar. Type a query to highlight and
jump to matches across the whole document; use the up/down arrows to step through them. Enter
replacement text and press **All** to replace every occurrence (a single undo step).

## API

The same capability is available programmatically on the controller:

```dart
final matches = controller.findMatches('hello');   // List<MatchLocation>
controller.selectMatch(matches.first);              // highlight one
controller.replaceMatch(matches.first, 'hi');       // replace one
controller.replaceAll('hello', 'hi');               // replace all (one undo unit)
```
