# Diagrams (Mermaid)

Mermaid diagrams are written as a ` ```mermaid ` fenced block and are a first-class node in
the document. Rendering is **100% native Dart — no WebView, no JavaScript anywhere.** A native
diagram engine renders the supported types and degrades gracefully to a readable source card
for the rest.

## Flowcharts

![Native flowchart](../images/mermaid-flowchart.png)

````markdown
```mermaid
graph TD
A[Start] --> B{Choice}
B -->|yes| C[Do it]
B -->|no| D[Skip]
```
````

Supports `graph`/`flowchart` with `TD`/`LR` directions, node shapes (`[rect]`, `(rounded)`,
`{diamond}`, `((circle))`), and labeled edges, laid out in layers.

## Pie charts

![Native pie chart](../images/mermaid-pie.png)

````markdown
```mermaid
pie title Languages
"Dart" : 70
"YAML" : 20
"Other" : 10
```
````

## Sequence diagrams

![Native sequence diagram](../images/mermaid-sequence.png)

````markdown
```mermaid
sequenceDiagram
  Alice->>Bob: Hello Bob
  Bob-->>Alice: Hi Alice
```
````

## State diagrams

State diagrams render natively too (reusing the flowchart layout):

````markdown
```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Running : start
  Running --> [*]
```
````

## Other types

Diagram types the native engine doesn't yet support (e.g. class, gantt, ER) degrade
gracefully to a readable **source card** with a `mermaid` badge:

![Mermaid source-card fallback](../images/mermaid.png)

You can also plug in your own renderer via the `diagramRenderer` parameter of
`MarkdownEditor`.
