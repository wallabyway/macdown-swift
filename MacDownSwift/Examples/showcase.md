# MacDown 2 showcase

> Turn on **Settings → Rendering → TeX math** for the formulas. Diagrams render with Pele (look: *White*) by default.

A **modern** rewrite with *SwiftUI* and `WKWebView`. ~~Old WebView~~ is gone.

## Lists

- [x] Swift 6
- [ ] Tasks
  - nested item
1. First
2. Second

> Blockquote with a [link](https://example.com) and an autolink https://apple.com.

| Feature | Status | Notes |
|---------|:------:|-------|
| :table: Tables | :circle-check: | GFM pipes |
| :file-text: Footnotes[^1] | :circle-check: | cmark-gfm |
| :zap: Pele diagrams | :circle-check: | looks + motion |
| :globe: Old WebView | :circle-x: | gone |

Icons are [Lucide](https://lucide.dev) shortcodes: `:rocket:` :rocket: `:database:` :database: `:shield:` :shield: `:lightbulb:` :lightbulb:

```swift
struct Hello: View {
    var body: some View { Text("Hello, world") }
}
```

Math: $e^{i\pi} + 1 = 0$ and

$$\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$$

```mermaid
flowchart LR
  A[fa:fa-pencil Editor] --> B(fa:fa-cpu Renderer) --> C{Preview?}
  C -->|fa:fa-check| D([fa:fa-eye WKWebView])
  C -->|fa:fa-x| E[fa:fa-file-text HTML export]
```

```mermaid
flowchart LR
  subgraph App[fa:fa-layers MacDown]
    direction TB
    E[fa:fa-pencil Editor] --> R[fa:fa-cpu cmark-gfm]
  end
  subgraph Web[fa:fa-globe WKWebView]
    direction TB
    P[fa:fa-eye Preview] --> D[fa:fa-zap Pele]
  end
  R -->|HTML| P
```

```mermaid
gantt
  title MacDown 2 Plan
  dateFormat YYYY-MM-DD
  section Core
  Renderer      :done,   r1, 2026-10-01, 5d
  Editor        :active, e1, after r1, 7d
  section Polish
  Themes        :        t1, after e1, 4d
  Export        :        x1, after e1, 3d
```

```mermaid
sequenceDiagram
  participant E as Editor
  participant R as Renderer
  participant P as Preview
  E->>R: fa:fa-pencil text changed
  R-->>P: HTML
  P->>P: highlight, math, diagrams
  E->>P: fa:fa-refresh scroll sync
```

```mermaid
pie title Code by area
  "Editor" : 45
  "Preview" : 25
  "Rendering" : 20
  "Settings" : 10
```

---

[^1]: A footnote.
