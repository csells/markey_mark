# Diagrams (Mermaid)

Mermaid diagrams are written as a ` ```mermaid ` fenced block and are a first-class node in
the document.

![Mermaid diagram block](../images/mermaid.png)

## Markdown

````markdown
```mermaid
graph TD;
  A[Start] --> B{Choice};
  B --> C[Done];
```
````

## Native rendering

Rendering is **100% native** — no WebView or JavaScript anywhere. A native Dart diagram engine
is being built in stages (by diagram type). **Pie charts already render natively:**

![Native pie chart](../images/mermaid-pie.png)

````markdown
```mermaid
pie title Languages
"Dart" : 70
"YAML" : 20
"Other" : 10
```
````

**Sequence diagrams** also render natively (lifelines, solid/dashed message arrows):

![Native sequence diagram](../images/mermaid-sequence.png)

````markdown
```mermaid
sequenceDiagram
  Alice->>Bob: Hello Bob
  Bob-->>Alice: Hi Alice
```
````

Diagram types not yet implemented degrade gracefully to a readable **source card** with a
`mermaid` badge (the flowchart above). You can also plug in your own renderer via the
`diagramRenderer` parameter of `MarkdownEditor`.
