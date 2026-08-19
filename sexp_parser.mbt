///|
/// A normalized AST node. `Text` nodes are HTML-escaped when rendered; `Raw`
/// holds trusted HTML emitted verbatim.
pub(all) enum SexpNode {
  Text(String)
  Comment(String)
  Raw(String)
  Element(String, Attrs, Array[SexpNode])
}

///|
priv enum ParsedListForm {
  Attr(String, String?)
  Nodes(SexpNode)
}

///|
priv enum ParsedHead {
  CommentHead
  RawTextHead
  AttributeHead(String)
  ElementHead(String)
}

///|
/// How a delimited term is scanned. `BareText` collapses whitespace runs to a
/// single space and stops at any unescaped parenthesis; the payload modes
/// preserve whitespace verbatim and differ only in their paren rules.
priv enum ScanMode {
  BareText
  Comment
  RawText
  Attribute
}

///|
/// The maximum nesting depth of elements; deeper input is rejected instead of
/// overflowing the call stack.
const MAX_NESTING_DEPTH = 128

///|
/// Parses a full S-expression HTML fragment into normalized AST nodes.
///
/// Returns `Err` with a `parse error at line L, column C: ...` message when the
/// source is not a valid fragment.
pub fn parse_sexp(source : String) -> Result[Array[SexpNode], String] {
  Ok(parse_document(Cursor::new(source))) catch {
    error => Err(Show::to_string(error))
  }
}

///|
/// Parses top-level nodes. Leading and trailing document whitespace is
/// structural and dropped; whitespace between top-level nodes is content.
fn parse_document(start : Cursor) -> Array[SexpNode] raise ParseError {
  let nodes : Array[SexpNode] = []
  let mut cursor = start.skip_whitespace()
  let mut last_bare = false
  while !cursor.is_end() {
    if cursor.peek() is Some(ch) && is_sexp_close_paren(ch) {
      raise cursor.error("unmatched ')' at the top level")
    }
    let (next, bare) = parse_node(cursor, nodes, 0)
    cursor = next
    last_bare = bare
  }
  if last_bare {
    match nodes.last() {
      Some(Text(text)) if text.is_blank() => ignore(nodes.pop())
      _ => ()
    }
  }
  nodes
}

///|
/// Parses one root item, appending it to `nodes`. `#` and `%` heads and explicit
/// nodes are not trailing-trimmable; bare text is, which `last_bare` records.
/// The caller guarantees the cursor is at a non-whitespace, non-`)` character.
fn parse_node(
  cursor : Cursor,
  nodes : Array[SexpNode],
  depth : Int,
) -> (Cursor, Bool) raise ParseError {
  if is_sexp_open_paren(cursor.unsafe_char_at(cursor.index)) {
    let (item, next) = parse_list_form(cursor, depth)
    match item {
      Nodes(node) => {
        nodes.push(node)
        (next, false)
      }
      Attr(_, _) =>
        raise cursor.error("attribute cannot appear at the document root")
    }
  } else {
    let (text, next) = parse_text(cursor)
    nodes.push(Text(text))
    (next, true)
  }
}

///|
/// Reads the list head and dispatches the rest of the list to the matching
/// payload parser.
fn parse_list_form(
  open : Cursor,
  depth : Int,
) -> (ParsedListForm, Cursor) raise ParseError {
  let (head, after_head) = parse_list_form_head(open)
  head.parse_payload(after_head, depth)
}

///|
fn parse_list_form_head(open : Cursor) -> (ParsedHead, Cursor) raise ParseError {
  let head_start = open.advance_code_units(1).skip_whitespace()
  guard head_start.peek() is Some(ch) else {
    raise open.error("unterminated list")
  }
  guard !is_sexp_close_paren(ch) else {
    raise open.error("empty list is invalid")
  }
  parse_head(head_start)
}

///|
/// Reads and classifies a list head. `#` and `%` are single-character markers
/// whose payload follows immediately and is not token-delimited; `:name` is an
/// attribute; any other token up to whitespace or a list boundary is a tag.
fn parse_head(start : Cursor) -> (ParsedHead, Cursor) raise ParseError {
  let ch = start.unsafe_char_at(start.index)
  match ch {
    '#' => (RawTextHead, start.advance_code_units(1))
    '%' => (CommentHead, start.advance_code_units(1))
    ':' => {
      let (name, after_head) = parse_head_token(start, 1)
      guard !name.is_empty() else {
        raise after_head.error("attribute name cannot be empty")
      }
      (AttributeHead(name), after_head)
    }
    _ => {
      let (tag, after_head) = parse_head_token(start, 0)
      guard !tag.is_empty() else {
        raise start.error("list head cannot be empty")
      }
      (ElementHead(tag), after_head)
    }
  }
}

///|
/// Reads a head token starting `skip` code units past `start`, up to whitespace
/// or a list boundary, without copying the skipped marker character.
fn parse_head_token(start : Cursor, skip : Int) -> (String, Cursor) {
  let mut index = start.index + skip
  while index < start.code_unit_length() {
    let ch = start.unsafe_char_at(index)
    if is_sexp_paren(ch) || ch.is_whitespace() {
      break
    }
    index = start.next_char_index(index)
  }
  (
    start.source.sub(start=start.index + skip, end=index).to_owned(),
    start.with_index(index),
  )
}

///|
fn ParsedHead::parse_payload(
  self : ParsedHead,
  after_head : Cursor,
  depth : Int,
) -> (ParsedListForm, Cursor) raise ParseError {
  match self {
    CommentHead => parse_comment(after_head)
    RawTextHead => parse_raw_text(after_head)
    AttributeHead(name) => parse_attribute(after_head, name)
    ElementHead(tag) => parse_element(after_head, tag, depth)
  }
}

///|
/// Parses `(% payload)`. Separator whitespace after `%` is not comment content;
/// the payload parser then keeps balanced parentheses until the closing list paren.
fn parse_comment(
  after_head : Cursor,
) -> (ParsedListForm, Cursor) raise ParseError {
  let start = after_head.skip_whitespace()
  let (content, next) = scan_delimited(start, Comment)
  (Nodes(Comment(content)), next)
}

///|
/// Parses `(# payload)`. The content after `#` is literal and verbatim: no
/// whitespace is consumed as a separator, only `\(` and `\)` are unescaped.
fn parse_raw_text(
  after_head : Cursor,
) -> (ParsedListForm, Cursor) raise ParseError {
  let (content, next) = scan_delimited(after_head, RawText)
  (Nodes(Text(content)), next)
}

///|
/// Parses `(:name)` and `(:name value)`. Attribute values are plain text only;
/// nested list structure is intentionally rejected by the payload scanner.
fn parse_attribute(
  after_head : Cursor,
  name : String,
) -> (ParsedListForm, Cursor) raise ParseError {
  let cursor = after_head.skip_whitespace()
  guard cursor.peek() is Some(ch) else {
    raise cursor.error("unterminated attribute")
  }
  guard !is_sexp_close_paren(ch) else {
    return (Attr(name, None), cursor.advance_code_units(1))
  }
  let (value, next) = scan_delimited(cursor, Attribute)
  (Attr(name, Some(value)), next)
}

///|
/// Parses an element body, collecting attributes and children in source order.
/// Attribute forms may appear anywhere; they are hoisted onto the element and
/// the whitespace immediately around them is structural (dropped). `depth` is
/// the nesting level of this element (0-based) and is capped at
/// `MAX_NESTING_DEPTH` to bound recursion.
fn parse_element(
  after_head : Cursor,
  tag : String,
  depth : Int,
) -> (ParsedListForm, Cursor) raise ParseError {
  guard depth < MAX_NESTING_DEPTH else {
    raise after_head.error("nesting depth exceeds 128")
  }
  let attrs : Attrs = Attrs({})
  let children : Array[SexpNode] = []
  let mut last_bare = false
  let mut cursor = after_head.skip_whitespace()
  while !cursor.is_end() {
    match cursor.peek() {
      Some(ch) if is_sexp_close_paren(ch) =>
        return build_element_result(tag, attrs, children, cursor)
      Some(ch) if is_sexp_open_paren(ch) => {
        let (next, bare) = parse_element_list_item(
          cursor,
          attrs,
          children,
          last_bare,
          depth + 1,
        )
        cursor = next
        last_bare = bare
      }
      _ => {
        let (next, bare) = parse_element_text(cursor, children)
        cursor = next
        last_bare = bare
      }
    }
  }
  raise cursor.error("unterminated element <" + tag + ">")
}

///|
/// Builds the element result after the closing paren, applying void-element
/// rules at the boundary where all children are known.
fn build_element_result(
  tag : String,
  attrs : Attrs,
  children : Array[SexpNode],
  close : Cursor,
) -> (ParsedListForm, Cursor) raise ParseError {
  if is_void_element_name(tag) && !children.is_empty() {
    raise close.error("void element <" + tag + "> cannot have child nodes")
  }
  (Nodes(Element(tag, attrs, children)), close.advance_code_units(1))
}

///|
/// Handles one parenthesized item inside an element. Attribute forms are
/// hoisted onto the element and their surrounding whitespace is structural;
/// child nodes are appended as content.
fn parse_element_list_item(
  cursor : Cursor,
  attrs : Attrs,
  children : Array[SexpNode],
  last_bare : Bool,
  depth : Int,
) -> (Cursor, Bool) raise ParseError {
  let (item, next) = parse_list_form(cursor, depth)
  match item {
    Attr(name, value) => {
      trim_trailing_text_before_attribute(children, last_bare)
      Attrs::upsert(attrs, name, value)
      (next.skip_whitespace(), false)
    }
    Nodes(node) => {
      children.push(node)
      (next, false)
    }
  }
}

///|
/// Reads a bare text child, recording whether it is the trailing (trimmable)
/// node.
fn parse_element_text(
  cursor : Cursor,
  children : Array[SexpNode],
) -> (Cursor, Bool) raise ParseError {
  let (text, next) = parse_text(cursor)
  if !text.is_empty() {
    children.push(Text(text))
  }
  (next, !text.is_empty())
}

///|
/// Reads ordinary text until an unescaped list boundary. Only `\(` and `\)`
/// are unescaped; other backslashes remain literal text. Within a text term,
/// every run of whitespace collapses to a single space.
fn parse_text(start : Cursor) -> (String, Cursor) raise ParseError {
  scan_delimited(start, BareText)
}

///|
/// Scans one delimited term. A fast path scans UTF-16 code units directly and
/// extracts the term with `sub` when no escape, whitespace run, or paren rule
/// requires a transformation; otherwise the shared slow path rebuilds it.
fn scan_delimited(
  start : Cursor,
  mode : ScanMode,
) -> (String, Cursor) raise ParseError {
  let source = start.source
  let length = start.code_unit_length()
  let mut index = start.index
  let mut comment_depth = 0
  while index < length {
    let code = source.code_unit_at(index).to_int()
    if code == 0x5C {
      break
    }
    match mode {
      BareText =>
        if code < 0x80 {
          if code == 0x28 || code == 0x29 {
            return (start.slice_until(index), start.with_index(index))
          }
          if code >= 0x09 && code <= 0x0D {
            break
          }
          if code == 0x20 &&
            index + 1 < length &&
            is_ascii_whitespace_code(source.code_unit_at(index + 1).to_int()) {
            break
          }
          index = index + 1
        } else {
          let ch = source.get_char(index).unwrap()
          if ch.is_whitespace() {
            break
          }
          index = index + ch.utf16_len()
        }
      Comment | RawText | Attribute => {
        match code {
          0x28 =>
            match mode {
              Comment => comment_depth = comment_depth + 1
              Attribute =>
                raise start
                  .with_index(index)
                  .error("attribute values must be plain text")
              _ => ()
            }
          0x29 =>
            match mode {
              Comment => {
                if comment_depth == 0 {
                  return (start.slice_until(index), start.with_index(index + 1))
                }
                comment_depth = comment_depth - 1
              }
              _ =>
                return (start.slice_until(index), start.with_index(index + 1))
            }
          _ => ()
        }
        index = index + 1
      }
    }
  }
  scan_delimited_with_transform(start, mode)
}

///|
/// Slow path of `scan_delimited`: resolves `\(`/`\)`, collapses whitespace runs
/// in bare text, and tracks balanced parentheses in comments.
fn scan_delimited_with_transform(
  start : Cursor,
  mode : ScanMode,
) -> (String, Cursor) raise ParseError {
  let buffer : Array[Char] = []
  let mut index = start.index
  let mut comment_depth = 0
  while index < start.code_unit_length() {
    let ch = start.unsafe_char_at(index)
    if ch == '\\' {
      match consume_escaped_paren_into(start, index, buffer) {
        Some(next) => {
          index = next
          continue
        }
        None => ()
      }
    } else {
      match mode {
        BareText =>
          if is_sexp_paren(ch) {
            return (text_from_buffer(buffer), start.with_index(index))
          } else if ch.is_whitespace() {
            buffer.push(' ')
            while index < start.code_unit_length() &&
                  start.unsafe_char_at(index).is_whitespace() {
              index = start.next_char_index(index)
            }
            continue
          }
        Comment =>
          if ch == '(' {
            comment_depth = comment_depth + 1
          } else if ch == ')' {
            if comment_depth == 0 {
              return (text_from_buffer(buffer), start.with_index(index + 1))
            }
            comment_depth = comment_depth - 1
          }
        RawText =>
          if ch == ')' {
            return (text_from_buffer(buffer), start.with_index(index + 1))
          }
        Attribute =>
          if ch == '(' {
            raise start
              .with_index(index)
              .error("attribute values must be plain text")
          } else if ch == ')' {
            return (text_from_buffer(buffer), start.with_index(index + 1))
          }
      }
    }
    buffer.push(ch)
    index = start.next_char_index(index)
  }
  match mode {
    BareText => (text_from_buffer(buffer), start.with_index(index))
    Comment => raise start.with_index(index).error("unterminated comment")
    RawText =>
      raise start.with_index(index).error("unterminated (# ...) text node")
    Attribute => raise start.with_index(index).error("unterminated attribute")
  }
}

///|
fn text_from_buffer(buffer : Array[Char]) -> String {
  String::from_array(buffer.view())
}

///|
/// Consumes `\(` or `\)` as a literal paren and returns the next code-unit
/// index. Other backslashes are left for the caller to copy unchanged.
fn consume_escaped_paren_into(
  source : Cursor,
  index : Int,
  buffer : Array[Char],
) -> Int? {
  guard index + 1 < source.code_unit_length() else { return None }
  let escaped = source.unsafe_char_at(index + 1)
  guard is_sexp_text_escape_target(escaped) else { return None }
  buffer.push(escaped)
  Some(index + 2)
}

///|
/// If an attribute follows a bare text term, its trailing whitespace is
/// structural and is trimmed (or the term removed if it was only whitespace).
fn trim_trailing_text_before_attribute(
  children : Array[SexpNode],
  last_bare : Bool,
) -> Unit {
  guard last_bare && !children.is_empty() else { return }
  let last_index = children.length() - 1
  match children[last_index] {
    Text(text) => {
      let trimmed = text.trim_end().to_owned()
      if trimmed.is_empty() {
        children.truncate(last_index)
      } else {
        children[last_index] = Text(trimmed)
      }
    }
    _ => ()
  }
}
