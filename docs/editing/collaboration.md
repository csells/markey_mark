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

## Concurrent conflict resolution (operational transform)

Genuinely *concurrent* edits — two peers changing the document before they've
seen each other's change — are reconciled with operational transformation over
the same operation log. `transformOperation` / `transformTransaction` rewrite a
remote transaction so it applies cleanly after local concurrent edits, and both
peers converge (the TP1 property):

```dart
// Each peer applied its own edit; now reconcile the other's against it.
a.applyRemote(transformTransaction(remoteFromB, myLocalA, tieBreak: false));
b.applyRemote(transformTransaction(remoteFromA, myLocalB, tieBreak: true));
// a.markdown == b.markdown
```

- **Structural concurrency** (inserting/deleting different blocks) is reconciled
  by shifting block indices.
- **Same-block conflicts** (two peers editing one block at once) are resolved by
  a deterministic `tieBreak` — derive it from a stable site id so the same side
  wins on every peer.

A networked transport drives this by tracking which transactions each peer has
seen (a version vector or a client-server order) and calling
`transformTransaction` before applying. The transforms themselves are pure and
fully tested for convergence.
