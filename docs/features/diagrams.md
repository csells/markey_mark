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

## Rendering

Rendering is **100% native** — there is no WebView or JavaScript anywhere in the editor. A
native Dart diagram engine is being built in stages (by diagram type); until a given diagram
type is supported it degrades gracefully to a readable **source card** (shown above) with a
`mermaid` badge. You can also plug in your own renderer via the `diagramRenderer` parameter of
`MarkdownEditor`.
