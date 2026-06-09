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

## Convergent sessions (`OtCollaborationSession`)

`OtCollaborationSession` wires the transforms into the runtime, so peers can edit
**concurrently** and still converge — you don't call `transformTransaction`
yourself:

```dart
final session = OtCollaborationSession([a, b]);
// a and b edit at the same time (delivery buffered):
a.insertText('!');   // applied on a immediately
b.insertText('?');   // applied on b immediately
session.flush();     // a transport drives this on receive
// a.markdown == b.markdown — both edits reconciled
```

It uses a Jupiter-style relay: each peer applies its edits optimistically; on
`flush` every buffered op is server-transformed against the canonical ops its
sender hadn't seen, then delivered to each other peer client-transformed against
that peer's still-pending ops, and acknowledged to the sender. Different-block
edits merge losslessly, and two people editing the **same paragraph** both keep
their work: concurrent same-block edits — inserts, deletes, *and* formatting —
are merged with **character-level operational transform** (`DeltaChange`, the
retain/insert/delete change model: `diff` → `transform` → `apply`), so every
peer converges to the same merged document. The transform is property-tested
(500 random concurrent insert/delete/format edits always converge). A real
network transport drives `flush` on receive.

## Network transport

Transactions (and the nodes they carry, with **stable ids**) serialize to JSON
via `CollaborationWire`, so a real transport can ferry edits between processes:

```dart
final session = TransportCollaborationSession(controller, myTransport);
// local edits are encoded + sent; incoming edits are decoded + applied.
```

`CollaborationTransport` is the seam (`send(String)` + `Stream<String> incoming`)
— back it with a WebSocket, WebRTC data channel, etc. `LoopbackTransportPair`
wires two transports together for tests and same-process peers.
`CollaborationWire.encode/decode` round-trip a full `EditTransaction` (every
block type, selection, and tag), proven by `wire_test`.
