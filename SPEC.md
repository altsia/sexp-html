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

Spaces do not split text into separate terms. Text is greedy: it runs until the
next unescaped parenthesis.

Whitespace is never ambiguous because it follows one uniform rule, described in
[§ 2.1](#21-whitespace-model): runs of whitespace inside a text term become a
single space, and structural whitespace (around list heads and attribute forms,
and at the document edges) is dropped. When exact whitespace must be produced,
use the verbatim raw text form `(# ...)`.

## 2. Minimal grammar

The grammar below is intentionally lexical-light. Text is defined by exclusion:
anything up to the next unescaped parenthesis.

```ebnf
document        ::= node*

node            ::= text | list

list            ::= "(" list-content* ")"

list-content    ::= node

text            ::= bare-text | raw-text

bare-text       ::= char*

raw-text        ::= "(" "#" raw-char* ")"

char            ::= escaped-lparen
                  | escaped-rparen
                  | any character except unescaped "(" or ")"

raw-char        ::= escaped-lparen
                  | escaped-rparen
                  | any character except unescaped ")"
```

List meaning depends on its first item:

- `(% ...)` → comment
- `(# ...)` → verbatim raw text node
- `(:name ...)` → attribute
- `(tag ...)` → element, where `tag` is a non-empty text term
- anything else → invalid

The heads `#` and `%` are single characters: their payload follows immediately
and is not token-delimited, so `(#hello)` and `(%hello)` are valid. All other
heads are tokens read up to whitespace or a parenthesis.

### 2.1 Whitespace model

Whitespace is a space, tab, or newline. There are two kinds:

- **Structural whitespace** is dropped and never appears in the output. It is:
  - whitespace immediately after a list head token (it only separates the head
    from the first item);
  - whitespace immediately around an attribute form (attributes are hoisted out
    of the content flow, so this whitespace is layout, not content);
  - whitespace at the very start and end of the document.
- **Content whitespace** is preserved:
  - inside a bare text term, every run of whitespace collapses to a single space;
  - inside `(# ...)`, whitespace is preserved character-for-character;
  - inside an attribute value, whitespace is preserved as written.

Because text is delimited by parentheses rather than whitespace, this is one text
term:

```sexp
One hundred million and two thousand years from now
```

## 3. Core forms

### 3.1 Element

```sexp
(tag item1 item2 ...)
```

- `tag` is the element name
- `tag` must not be empty
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

- any whitespace immediately after `%` is only a separator and is not part of the comment payload
- unescaped parentheses inside the comment payload must still be balanced, or be written as `\(` and `\)`

Example:

```sexp
(% I want you to know since you came in my life)
```

```html
<!-- I want you to know since you came in my life -->
```

### 3.3 Raw Text

```sexp
(# ...)
```

- `(# ...)` serializes to a text node
- the exact form `(#)` is valid and denotes an empty text node
- its content is everything after `#` up to the first unescaped `)`, taken
  **verbatim**: no whitespace is consumed as a separator, and leading spaces and
  newlines are preserved exactly
- inside this form, `\(` becomes `(` and `\)` becomes `)`

Examples:

```sexp
(#)
(#hello)
(# hello)
(#  world)
(#\nworld)
(# \(hello\))
```

serialize to the text `""`, `"hello"`, `" hello"`, `"  world"`, `"\nworld"`, and
`"(hello)"` respectively.

### 3.4 Attribute

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

A bare text term is any continuous span of text up to the next unescaped `(` or
`)`. Inside it, **every run of whitespace collapses to a single space**.

Consequences:

- `(p one   two)` renders `<p>one two</p>`
- `(p line1\nline2)` renders `<p>line1 line2</p>` (a newline is a space)
- `(p   hello)` renders `<p>hello</p>` (whitespace after the head is structural)
- `(p a (b c))` renders `<p>a <b>c</b></p>` and `(p a(b c))` renders
  `<p>a<b>c</b></p>`: the whitespace you type between a text term and an element
  is content (one space), and typing nothing gives adjacency
- when text must preserve exact spacing (multiple spaces, tabs, newlines, leading
  or trailing whitespace), use `(# ...)`

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

Inside `(# ...)`, the same parenthesis escaping rules apply.

A literal backslash is ordinary text except directly before the closing `)`
of a term, where `\)` is always an escape. A text value ending in a backslash
is therefore not representable, and `html_to_sexp` rejects it.

### 4.3 Attributes

Attributes may appear anywhere inside an element. Because they are hoisted onto
the opening tag, the whitespace immediately around an attribute form is
structural and does not appear in the output.

Example:

```sexp
(div hello (:class x))
```

```html
<div class="x">hello</div>
```

Attribute values must be plain text only.

- leading whitespace in an attribute value is not representable in this notation
- therefore `html_to_sexp` must reject HTML attributes whose value begins with whitespace
- this notation does not distinguish an explicit empty-string attribute value from a minimized / valueless HTML attribute; both canonicalize to `(:name)` when converting from HTML

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

Explicit raw text nodes are different: their payload remains literal even if a
later attribute appears.

Example:

```sexp
(div (#  ) (:class x))
```

```html
<div class="x">  </div>
```

### 4.4 Comments

Comment contents are not recursively interpreted as HTML structure.

- when converting HTML back to this notation, comment text is canonicalized by trimming leading and trailing whitespace

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

For `(# ...)`:

1. take every character after `#` up to the first unescaped `)`
2. resolve `\(` to `(` and `\)` to `)`
3. emit the resulting text verbatim

Consequences:

- `(#)` and `(# )` serialize to `""` and `" "` respectively
- `(#  )` serializes to two literal spaces
- `(#\nhello)` serializes to `\nhello`

### 5.4 Fragment model

A document is an HTML fragment, not necessarily a single rooted tree. Multiple
top-level nodes are allowed.

Lists whose first item is missing or is itself another list are invalid.

### 5.5 Converting HTML back (`html_to_sexp`)

`html_to_sexp` emits S-expressions that round-trip to the same HTML:

- a text node with no leading whitespace and only single internal space
  characters is emitted as a bare term; any other text is emitted as `(# ...)`
- a text, attribute-value, or comment value ending in a backslash is rejected as
  unrepresentable
- attribute values beginning with whitespace are rejected as unrepresentable
- child terms are concatenated directly (a bare text term is only emitted when it
  is safe next to its neighbors)

## 6. Examples

### Comments

```sexp
(% I want you to know since you came in my life)
```

```html
<!-- I want you to know since you came in my life -->
```

### Whitespace collapses to one space

```sexp
(p One hundred million and two thousand years from now   end)
```

```html
<p>One hundred million and two thousand years from now end</p>
```

### Spaces around elements are content

```sexp
(p One hundred million and two thousand years from now
  (span (:style font-family: "Alegreya Sans SC", sans-serif)
        爱してる))
```

```html
<p>One hundred million and two thousand years from now <span style="font-family: &quot;Alegreya Sans SC&quot;, sans-serif">爱してる</span></p>
```

### Exact spacing uses raw text

```sexp
(p hello (#  ) world)
```

```html
<p>hello    world</p>
```

Four spaces between `hello` and `world`: the raw payload `"  "` plus one content space on each side (§ 4.1).

### Adjacency

```sexp
(p a(b c)d)
```

```html
<p>a<b>c</b>d</p>
```

### Escaped parentheses

```sexp
(details (:open)
  (summary every day every night)
  \(I've been waiting to share my love with you\)
  you give light into the darkness skies)
```

```html
<details open><summary>every day every night</summary> (I've been waiting to share my love with you) you give light into the darkness skies</details>
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
