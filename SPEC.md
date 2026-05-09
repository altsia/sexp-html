# Specification

A minimal S-expression syntax for HTML fragments.

## 1. Overview

This notation represents HTML using parenthesized structure.

Example:

```sexp
(p hello)
```

```html
<p>hello</p>
```

It is designed around one rule:

> Structure is delimited only by unescaped `(` and `)`.

Spaces do not split text into separate terms.

## 2. Minimal grammar

The grammar below is intentionally lexical-light. Text is defined by exclusion: anything up to the next unescaped parenthesis.

```ebnf
document        ::= node*

node            ::= text | list

list            ::= "(" list-content* ")"

list-content    ::= node

text            ::= char*

char            ::= escaped-lparen
                  | escaped-rparen
                  | any character except unescaped "(" or ")"

escaped-lparen  ::= "\("
escaped-rparen  ::= "\)"
```

List meaning depends on its first item:

- `(% ...)` → comment
- `(tag ...)` → element, where `tag` is a text term
- anything else → invalid

Because text is delimited by parentheses rather than whitespace, this is one text term:

```sexp
One hundred million and two thousand years from now
```

## 3. Core forms

### 3.1 Element

```sexp
(tag item1 item2 ...)
```

- `tag` is the element name
- each remaining item is either an attribute or a child node

Example:

```sexp
(span (:class note) hello)
```

```html
<span class="note">hello</span>
```

### 3.2 Comment

```sexp
(% comment text)
```

Example:

```sexp
(% I want you to know since you came in my life)
```

```html
<!-- I want you to know since you came in my life -->
```

### 3.3 Attribute

```sexp
(:name value)
```

Boolean attribute:

```sexp
(:open)
```

Examples:

```sexp
(:class note)
(:id main)
(:open)
```

```html
class="note"
id="main"
open
```


## 4. Semantics

### 4.1 Text terms

A text term is any continuous span of text up to the next unescaped `(` or `)`.

Consequences:

- spaces are preserved inside text
- newlines are preserved inside text
- spaces between terms are only separators and do not create nodes

So in:

```sexp
(p One hundred million and two thousand years from now)
```

the entire phrase is a single child text node.

### 4.2 Escaping

Only parentheses require language-level escaping:

- `\(` → `(`
- `\)` → `)`

Example:

```sexp
\(hello\)
```

becomes:

```html
(hello)
```

### 4.3 Attributes

Attributes may appear anywhere inside an element.

Example:

```sexp
(div hello (:class x))
```

```html
<div class="x">hello</div>
```

Attribute values must be plain text only.

Valid:

```sexp
(:title hello world)
(:style font-family: "Alegreya Sans SC", sans-serif)
```

Invalid:

```sexp
(:title (b hello))
```

If an attribute appears multiple times, the last occurrence overrides earlier ones.

Example:

```sexp
(div (:class a) (:class b) hello)
```

```html
<div class="b">hello</div>
```

### 4.4 Comments

Comment contents are not recursively interpreted as HTML structure.

Example:

```sexp
(% hello (b world))
```

```html
<!-- hello (b world) -->
```

### 4.5 Void elements

Void elements follow normal HTML serialization rules and do not emit closing tags.

Example:

```sexp
(br)
(img (:src cover.png) (:alt cover))
```

```html
<br>
<img src="cover.png" alt="cover">
```

A void element with child nodes is a semantic error.

Invalid:

```sexp
(br hello)
```


## 5. Serialization rules

### 5.1 Text

Text nodes must be HTML-escaped as usual:

- `&` → `&amp;`
- `<` → `&lt;`
- `>` → `&gt;`

### 5.2 Attribute values

Attribute values must be HTML-escaped for the chosen quoting style.

Example:

```sexp
(:style font-family: "Alegreya Sans SC", sans-serif)
```

may serialize as:

```html
style="font-family: &quot;Alegreya Sans SC&quot;, sans-serif"
```

### 5.3 Element serialization

For an element:

1. read the first item as the tag name
2. collect all attribute forms `(:name ...)`
3. resolve duplicate attributes by keeping the last one
4. serialize all non-attribute items in order as children
5. emit normal HTML, except for void elements

### 5.4 Fragment model

A document is an HTML fragment, not necessarily a single rooted tree. Multiple top-level nodes are allowed.


## 6. Examples

### Comments

```sexp
(% I want you to know since you came in my life)
```

```html
<!-- I want you to know since you came in my life -->
```

### Text with spaces

```sexp
(p One hundred million and two thousand years from now)
```

```html
<p>One hundred million and two thousand years from now</p>
```

### Nested structure

```sexp
(p One hundred million and two thousand years from now
  (span (:style font-family: "Alegreya Sans SC", sans-serif)
        爱してる))
```

```html
<p>One hundred million and two thousand years from now
  <span style="font-family: &quot;Alegreya Sans SC&quot;, sans-serif">爱してる</span>
</p>
```

### Escaped parentheses

```sexp
(details (:open)
  (summary every day every night)
  \(I've been waiting to share my love with you\)
  you give light into the darkness skies)
```

```html
<details open>
  <summary>every day every night</summary>
  (I've been waiting to share my love with you)
  you give light into the darkness skies
</details>
```

### Attribute after children

```sexp
(div hello (:class x))
```

```html
<div class="x">hello</div>
```

### Duplicate attributes

```sexp
(div (:class a) (:class b) hello)
```

```html
<div class="b">hello</div>
```
