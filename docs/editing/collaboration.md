# Real-time collaboration

Edits are invertible operations on the document, so they can be applied to a remote replica.
`CollaborationSession` connects multiple editors so an edit on one is applied to the others in
real time — the collaboration seam built on the operation log.

```dart
final a = MarkdownEditorController(markdown: doc);
final b = MarkdownEditorController(markdown: doc);
final session = CollaborationSession([a, b]);
// ...edits on `a` now appear on `b`, and vice versa.
session.dispose(); // stop syncing
```

A network transport plugs in here by serializing the transactions between processes.

!!! note
    This is the in-process foundation. Non-conflicting edits (different blocks, or turn-taking)
    stay consistent; genuinely **concurrent conflicting** edits need operational transform or a
    CRDT layered on the same op log — the architecture is designed to allow that without
    changing the editing core.
