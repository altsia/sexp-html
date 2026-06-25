# S-Expression Notation for HTML

## Example

- keep comments
  
  ```sexp
  (% I want you to know since you came in my life)
  ```

  ```html
  <!-- I want you to know since you came in my life -->
  ```

- syntactic white spaces between terms will be ignored

  ```sexp
  (p One hundred million and two thousand years from now 
    (span (:style font-family: "Alegreya Sans SC", sans-serif) 
            爱してる) )
  ```

  ```html
  <p>One hundred million and two thousand years from now 
    <span style="font-family: \"Alegreya Sans SC\", sans-serif">爱してる</span>
  </p>
  ```

- only parentheses need to be escaped

  ```sexp
  (details (:open) 
    (summary every day every night) 
    \(I've been waiting to share my love with you\) 
    you give light into the darkness skies )
  ```

  ```html
  <details open>
    <summary>every day every night</summary>
    (I've been waiting to share my love with you)
    you give light into the darkness skies
  </details>
  ```

- `(~)` emits a literal space, and `(~tag ...)` emits the normal element with one space on each side

  ```sexp
  (p (~span hello)world)
  ```

  ```html
  <p> <span>hello</span> world</p>
  ```

- `(# ...)` emits an explicit raw text node and preserves the text after `#` exactly, including leading spaces and newlines

  The first whitespace character after `#` is only a separator and is not part of the text payload.

  ```sexp
  (p (span hello) (#  world))
  ```

  ```html
  <p><span>hello</span> world</p>
  ```

## Specification

see [SPEC.md](./SPEC.md). 

## AST transform API

For custom forms that should become normal HTML-shaped nodes, parse to the public AST, transform it, then render it:

```moonbit
parse_sexp_html("(p (icon search))").map(transform).map(render_html)
```

The public AST is normalized to HTML-shaped nodes:

```moonbit
pub(all) enum SexpNode {
  Text(String)
  Comment(String)
  RawHtml(String)
  Element(String, HtmlAttrs, Array[SexpNode])
}
```

Syntax forms such as `(# ...)`, `(~)`, and `(~tag ...)` are expanded during parsing into ordinary `Text` and `Element` nodes.

Use `RawHtml` for trusted HTML that should be inserted directly without escaping:

```moonbit
render_html([
  SexpNode::Element("p", HtmlAttrs({}), [
    SexpNode::Text("<escaped> "),
    SexpNode::RawHtml("<em>trusted</em>"),
  ]),
])
```

`sexp-html` also provides helpers for common HTML rendering operations:

```moonbit
let attrs : HtmlAttrs = HtmlAttrs({})
attrs.upsert("lang", Some("en"))
attrs.append_class("page")

render_open_tag("html", attrs)
render_html_document(attrs, head, body, Some("html"))
```
