///|
pub(all) enum SexpNode {
  Text(String)
  Comment(String)
  RawHtml(String)
  Element(String, Array[(String, String?)], Array[SexpNode])
}

///|
priv enum ParsedListItem {
  Attr(String, String?)
  Nodes(Array[(SexpNode, Bool)])
}

///|
priv enum ParsedHead {
  CommentHead
  RawTextHead
  SpaceHead
  SpacedElementHead(String)
  AttributeHead(String)
  ElementHead(String)
}

///|
pub fn parse_sexp_html(source : String) -> Result[Array[SexpNode], String] {
  parse_document(Cursor::new(source))
}

///|
fn parse_document(start : Cursor) -> Result[Array[SexpNode], String] {
  let nodes : Array[SexpNode] = []
  let mut cursor = start.skip_whitespace()
  while !cursor.is_end() {
    if cursor.peek() == Some(')') {
      return Err(cursor.error("unexpected ')'"))
    }
    match parse_node(cursor) {
      Ok((parsed_nodes, next)) => {
        append_parsed_nodes(nodes, parsed_nodes)
        cursor = next.skip_whitespace()
      }
      Err(error) => return Err(error)
    }
  }
  Ok(nodes)
}

///|
fn parse_node(
  cursor : Cursor,
) -> Result[(Array[(SexpNode, Bool)], Cursor), String] {
  match cursor.peek() {
    None => Err(cursor.error("unexpected end of input"))
    Some('(') =>
      parse_list_item(cursor).bind(item => {
        match item {
          (Nodes(nodes), next) => Ok((nodes, next))
          (Attr(_, _), _) =>
            Err(cursor.error("attribute cannot appear at the document root"))
        }
      })
    Some(')') => Err(cursor.error("unexpected ')'"))
    Some(_) => {
      let (text, next) = parse_text(cursor)
      Ok(([(Text(text), true)], next))
    }
  }
}

///|
fn parse_list_item(open : Cursor) -> Result[(ParsedListItem, Cursor), String] {
  parse_list_head(open).bind(result => {
    let (head, after_head) = result
    parse_list_payload(after_head, head)
  })
}

///|
fn parse_list_head(open : Cursor) -> Result[(ParsedHead, Cursor), String] {
  let head_start = open.advance(1).skip_whitespace()
  match head_start.peek() {
    None => return Err(open.error("unterminated list"))
    Some(')') => return Err(open.error("empty list is invalid"))
    _ => ()
  }

  let (head, after_head) = parse_head(head_start)
  if head.is_empty() {
    return Err(head_start.error("list head cannot be empty"))
  }
  classify_head(head, after_head.index).map(parsed_head => {
    (parsed_head, after_head)
  })
}

///|
fn classify_head(head : String, after_head : Int) -> Result[ParsedHead, String] {
  if head == "%" {
    return Ok(CommentHead)
  }
  if head == "#" {
    return Ok(RawTextHead)
  }
  if head == "~" {
    return Ok(SpaceHead)
  }
  if head.has_prefix("~") {
    return classify_spaced_element_head(head, after_head)
  }
  if head.has_prefix(":") {
    return classify_attribute_head(head, after_head)
  }
  Ok(ElementHead(head))
}

///|
fn classify_spaced_element_head(
  head : String,
  after_head : Int,
) -> Result[ParsedHead, String] {
  let tag = head.sub(start=1).to_owned()
  if tag.is_empty() {
    return Err(error_at(after_head, "empty ~ tag must use the exact form (~)"))
  }
  Ok(SpacedElementHead(tag))
}

///|
fn classify_attribute_head(
  head : String,
  after_head : Int,
) -> Result[ParsedHead, String] {
  let name = head.sub(start=1).to_owned()
  if name.is_empty() {
    return Err(error_at(after_head, "attribute name cannot be empty"))
  }
  Ok(AttributeHead(name))
}

///|
fn parse_list_payload(
  after_head : Cursor,
  head : ParsedHead,
) -> Result[(ParsedListItem, Cursor), String] {
  match head {
    CommentHead => parse_comment(after_head)
    RawTextHead => parse_raw_text(after_head)
    SpaceHead => parse_space(after_head)
    SpacedElementHead(tag) => parse_element_with_kind(after_head, tag, true)
    AttributeHead(name) => parse_attribute(after_head, name)
    ElementHead(tag) => parse_element(after_head, tag)
  }
}

///|
fn parse_comment(
  after_head : Cursor,
) -> Result[(ParsedListItem, Cursor), String] {
  let start = after_head.skip_whitespace()
  capture_comment_text(start).map(result => {
    let (content, next) = result
    (Nodes([(Comment(content), false)]), next)
  })
}

///|
fn parse_raw_text(
  after_head : Cursor,
) -> Result[(ParsedListItem, Cursor), String] {
  let start = if after_head.peek().map_or(false, ch => ch.is_whitespace()) {
    after_head.advance(1)
  } else {
    after_head
  }
  capture_raw_text(start).map(result => {
    let (content, next) = result
    (Nodes([(Text(content), false)]), next)
  })
}

///|
fn parse_space(after_head : Cursor) -> Result[(ParsedListItem, Cursor), String] {
  let cursor = after_head.skip_whitespace()
  match cursor.peek() {
    None => Err(after_head.error("unterminated (~) form"))
    Some(')') => Ok((Nodes([(Text(" "), false)]), cursor.advance(1)))
    _ => Err(cursor.error("(~) cannot contain attributes or children"))
  }
}

///|
fn parse_attribute(
  after_head : Cursor,
  name : String,
) -> Result[(ParsedListItem, Cursor), String] {
  let cursor = after_head.skip_whitespace()
  match cursor.peek() {
    None => Err(after_head.error("unterminated attribute"))
    Some(')') => Ok((Attr(name, None), cursor.advance(1)))
    _ =>
      capture_attribute_value(cursor).map(result => {
        let (value, next) = result
        (Attr(name, Some(value)), next)
      })
  }
}

///|
fn parse_element(
  after_head : Cursor,
  tag : String,
) -> Result[(ParsedListItem, Cursor), String] {
  parse_element_with_kind(after_head, tag, false)
}

///|
fn parse_element_with_kind(
  after_head : Cursor,
  tag : String,
  spaced : Bool,
) -> Result[(ParsedListItem, Cursor), String] {
  let attrs : Array[(String, String?)] = []
  let children : Array[(SexpNode, Bool)] = []
  let mut cursor = after_head.skip_whitespace()
  while !cursor.is_end() {
    match cursor.peek() {
      Some(')') => return close_element(tag, attrs, children, spaced, cursor)
      Some('(') =>
        match parse_element_list_item(cursor, attrs, children) {
          Ok(next) => cursor = next.skip_whitespace()
          Err(error) => return Err(error)
        }
      _ => cursor = parse_element_text(cursor, children).skip_whitespace()
    }
  }
  Err(after_head.error("unterminated element <" + tag + ">"))
}

///|
fn close_element(
  tag : String,
  attrs : Array[(String, String?)],
  children : Array[(SexpNode, Bool)],
  spaced : Bool,
  close : Cursor,
) -> Result[(ParsedListItem, Cursor), String] {
  if is_void_tag(tag) && !children.is_empty() {
    return Err(
      close.error("void element <" + tag + "> cannot have child nodes"),
    )
  }
  let element = Element(tag, attrs, parsed_node_values(children))
  if spaced {
    Ok(
      (
        Nodes([(Text(" "), false), (element, false), (Text(" "), false)]),
        close.advance(1),
      ),
    )
  } else {
    Ok((Nodes([(element, false)]), close.advance(1)))
  }
}

///|
fn parse_element_list_item(
  cursor : Cursor,
  attrs : Array[(String, String?)],
  children : Array[(SexpNode, Bool)],
) -> Result[Cursor, String] {
  parse_list_item(cursor).bind(item => {
    match item {
      (Attr(name, value), next) => {
        trim_trailing_text_before_attribute(children)
        upsert_attr(attrs, name, value)
        Ok(next)
      }
      (Nodes(nodes), next) => {
        append_internal_nodes(children, nodes)
        Ok(next)
      }
    }
  })
}

///|
fn parse_element_text(
  cursor : Cursor,
  children : Array[(SexpNode, Bool)],
) -> Cursor {
  let (text, next) = parse_text(cursor)
  if !text.is_empty() {
    children.push((Text(text), true))
  }
  next
}

///|
fn parse_head(start : Cursor) -> (String, Cursor) {
  let mut index = start.index
  while index < start.length() {
    let ch = start.unsafe_char_at(index)
    if ch == '(' || ch == ')' || ch.is_whitespace() {
      break
    }
    index = start.next_index(index)
  }
  (start.slice_to_string(index), start.at(index))
}

///|
fn parse_text(start : Cursor) -> (String, Cursor) {
  let buffer : Array[Char] = []
  let mut index = start.index
  while index < start.length() {
    let ch = start.unsafe_char_at(index)
    if ch == '\\' {
      match consume_escaped_paren(start, index, buffer) {
        Some(next) => {
          index = next
          continue
        }
        None => ()
      }
      buffer.push(ch)
      index = start.next_index(index)
      continue
    }
    if ch == '(' || ch == ')' {
      break
    }
    buffer.push(ch)
    index = start.next_index(index)
  }
  (String::from_array(buffer.view()), start.at(index))
}

///|
fn capture_comment_text(start : Cursor) -> Result[(String, Cursor), String] {
  let buffer : Array[Char] = []
  let mut index = start.index
  let mut depth = 0
  while index < start.length() {
    let ch = start.unsafe_char_at(index)
    if ch == '\\' {
      match consume_escaped_paren(start, index, buffer) {
        Some(next) => {
          index = next
          continue
        }
        None => ()
      }
      buffer.push(ch)
      index = start.next_index(index)
      continue
    }
    if ch == '(' {
      depth = depth + 1
      buffer.push(ch)
      index = start.next_index(index)
      continue
    }
    if ch == ')' {
      if depth == 0 {
        return Ok((String::from_array(buffer.view()), start.at(index + 1)))
      }
      depth = depth - 1
      buffer.push(ch)
      index = start.next_index(index)
      continue
    }
    buffer.push(ch)
    index = start.next_index(index)
  }
  Err(start.error("unterminated comment"))
}

///|
fn capture_raw_text(start : Cursor) -> Result[(String, Cursor), String] {
  let buffer : Array[Char] = []
  let mut index = start.index
  while index < start.length() {
    let ch = start.unsafe_char_at(index)
    if ch == '\\' {
      match consume_escaped_paren(start, index, buffer) {
        Some(next) => {
          index = next
          continue
        }
        None => ()
      }
      buffer.push(ch)
      index = start.next_index(index)
      continue
    }
    if ch == ')' {
      return Ok((String::from_array(buffer.view()), start.at(index + 1)))
    }
    buffer.push(ch)
    index = start.next_index(index)
  }
  Err(start.error("unterminated (# ...) text node"))
}

///|
fn capture_attribute_value(start : Cursor) -> Result[(String, Cursor), String] {
  let buffer : Array[Char] = []
  let mut index = start.index
  while index < start.length() {
    let ch = start.unsafe_char_at(index)
    if ch == '\\' {
      match consume_escaped_paren(start, index, buffer) {
        Some(next) => {
          index = next
          continue
        }
        None => ()
      }
      buffer.push(ch)
      index = start.next_index(index)
      continue
    }
    if ch == '(' {
      return Err(start.at(index).error("attribute values must be plain text"))
    }
    if ch == ')' {
      return Ok((String::from_array(buffer.view()), start.at(index + 1)))
    }
    buffer.push(ch)
    index = start.next_index(index)
  }
  Err(start.error("unterminated attribute"))
}

///|
fn consume_escaped_paren(
  source : Cursor,
  index : Int,
  buffer : Array[Char],
) -> Int? {
  if index + 1 >= source.length() {
    return None
  }
  let escaped = source.unsafe_char_at(index + 1)
  if escaped != '(' && escaped != ')' {
    return None
  }
  buffer.push(escaped)
  Some(index + 2)
}

///|
fn append_parsed_nodes(
  target : Array[SexpNode],
  nodes : Array[(SexpNode, Bool)],
) -> Unit {
  target.append(parsed_node_values(nodes))
}

///|
fn append_internal_nodes(
  target : Array[(SexpNode, Bool)],
  nodes : Array[(SexpNode, Bool)],
) -> Unit {
  target.append(nodes)
}

///|
fn parsed_node_values(nodes : Array[(SexpNode, Bool)]) -> Array[SexpNode] {
  nodes.map(parsed_node => {
    let (node, _) = parsed_node
    node
  })
}

///|
fn trim_trailing_text_before_attribute(
  children : Array[(SexpNode, Bool)],
) -> Unit {
  if children.is_empty() {
    return
  }
  let last_index = children.length() - 1
  match children[last_index] {
    (Text(text), true) => {
      let trimmed = text.trim_end().to_owned()
      if trimmed.is_empty() {
        children.truncate(last_index)
      } else {
        children[last_index] = (Text(trimmed), true)
      }
    }
    _ => ()
  }
}
