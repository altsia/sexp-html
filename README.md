# S-Expression Notation for HTML

## Example

- keep comments
  
  ```sexp
  (% I want you to know since you came in my life)
  ```

  ```html
  <!-- I want you to know since you came in my life -->
  ```

- runs of whitespace inside a text term collapse to a single space

  ```sexp
  (p One hundred million and two thousand years from now
    (span (:style font-family: "Alegreya Sans SC", sans-serif)
            爱してる) )
  ```

  ```html
  <p>One hundred million and two thousand years from now <span style="font-family: &quot;Alegreya Sans SC&quot;, sans-serif">爱してる</span></p>
  ```

- only parentheses need to be escaped

  ```sexp
  (details (:open) 
    (summary every day every night) 
    \(I've been waiting to share my love with you\) 
    you give light into the darkness skies )
  ```

  ```html
  <details open><summary>every day every night</summary> (I've been waiting to share my love with you) you give light into the darkness skies</details>
  ```

- `(~)` emits a literal space, and `(~tag ...)` emits the normal element with one space on each side

  ```sexp
  (p (~span hello)world)
  ```

  ```html
  <p> <span>hello</span> world</p>
  ```

- `(# ...)` emits a verbatim text node: everything after `#` is literal, including leading spaces and newlines. No whitespace is consumed as a separator.

  ```sexp
  (p (span hello) (#  world))
  ```

  ```html
  <p><span>hello</span>  world</p>
  ```

- whitespace you type around an element is content, so adjacency requires no space

  ```sexp
  (p a (b c))
  (p a(b c))
  ```

  ```html
  <p>a <b>c</b></p>
  <p>a<b>c</b></p>
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
