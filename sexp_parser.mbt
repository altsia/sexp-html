///|
pub(all) enum SexpNode {
  Text(String)
  Comment(String)
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
  parse_document(Cursor::new(source.to_array(), 0))
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
fn parse_node(cursor : Cursor) -> Result[(Array[(SexpNode, Bool)], Cursor), String] {
  match cursor.peek() {
    None => Err(cursor.error("unexpected end of input"))
    Some('(') =>
      parse_list_item(cursor).bind(fn(item) {
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
  match parse_list_head(open) {
    Ok((head, after_head)) => parse_list_payload(after_head, head)
    Err(error) => Err(error)
  }
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
  classify_head(head, after_head.index).map(fn(parsed_head) {
    (parsed_head, after_head)
  })
}

///|
fn classify_head(head : String, after_head : Int) -> Result[ParsedHead, String] {
  if head == "%" {
    Ok(CommentHead)
  } else if head == "#" {
    Ok(RawTextHead)
  } else if head == "~" {
    Ok(SpaceHead)
  } else if head.has_prefix("~") {
    let tag = head.sub(start=1).to_owned()
    if tag.is_empty() {
      Err(error_at(after_head, "empty ~ tag must use the exact form (~)"))
    } else {
      Ok(SpacedElementHead(tag))
    }
  } else if head.has_prefix(":") {
    let name = head.sub(start=1).to_owned()
    if name.is_empty() {
      Err(error_at(after_head, "attribute name cannot be empty"))
    } else {
      Ok(AttributeHead(name))
    }
  } else {
    Ok(ElementHead(head))
  }
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
  capture_comment_text(start).map(fn(result) {
    let (content, next) = result
    (Nodes([(Comment(content), false)]), next)
  })
}

///|
fn parse_raw_text(
  after_head : Cursor,
) -> Result[(ParsedListItem, Cursor), String] {
  let start = if after_head.peek().map_or(false, fn(ch) { ch.is_whitespace() }) {
    after_head.advance(1)
  } else {
    after_head
  }
  capture_raw_text(start).map(fn(result) {
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
      capture_attribute_value(cursor).map(fn(result) {
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
    Ok((
      Nodes([(Text(" "), false), (element, false), (Text(" "), false)]),
      close.advance(1),
    ))
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
  match parse_list_item(cursor) {
    Ok((Attr(name, value), next)) => {
      trim_trailing_text_before_attribute(children)
      upsert_attribute(attrs, name, value)
      Ok(next)
    }
    Ok((Nodes(nodes), next)) => {
      append_internal_nodes(children, nodes)
      Ok(next)
    }
    Err(error) => Err(error)
  }
}

///|
fn parse_element_text(cursor : Cursor, children : Array[(SexpNode, Bool)]) -> Cursor {
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
    let ch = start.char_at(index)
    if ch == '(' || ch == ')' || ch.is_whitespace() {
      break
    }
    index = index + 1
  }
  (start.slice_to_string(index), start.at(index))
}

///|
fn parse_text(start : Cursor) -> (String, Cursor) {
  let buffer : Array[Char] = []
  let mut index = start.index
  while index < start.length() {
    let ch = start.char_at(index)
    if ch == '\\' {
      if index + 1 < start.length() {
        let escaped = start.char_at(index + 1)
        if escaped == '(' || escaped == ')' {
          buffer.push(escaped)
          index = index + 2
          continue
        }
      }
      buffer.push(ch)
      index = index + 1
      continue
    }
    if ch == '(' || ch == ')' {
      break
    }
    buffer.push(ch)
    index = index + 1
  }
  (String::from_array(buffer.view()), start.at(index))
}

///|
fn capture_comment_text(start : Cursor) -> Result[(String, Cursor), String] {
  let buffer : Array[Char] = []
  let mut index = start.index
  let mut depth = 0
  while index < start.length() {
    let ch = start.char_at(index)
    if ch == '\\' {
      if index + 1 < start.length() {
        let escaped = start.char_at(index + 1)
        if escaped == '(' || escaped == ')' {
          buffer.push(escaped)
          index = index + 2
          continue
        }
      }
      buffer.push(ch)
      index = index + 1
      continue
    }
    if ch == '(' {
      depth = depth + 1
      buffer.push(ch)
      index = index + 1
      continue
    }
    if ch == ')' {
      if depth == 0 {
        return Ok(
          (
            String::from_array(buffer.view()),
            start.at(index + 1),
          ),
        )
      }
      depth = depth - 1
      buffer.push(ch)
      index = index + 1
      continue
    }
    buffer.push(ch)
    index = index + 1
  }
  Err(start.error("unterminated comment"))
}

///|
fn capture_raw_text(start : Cursor) -> Result[(String, Cursor), String] {
  let buffer : Array[Char] = []
  let mut index = start.index
  while index < start.length() {
    let ch = start.char_at(index)
    if ch == '\\' {
      if index + 1 < start.length() {
        let escaped = start.char_at(index + 1)
        if escaped == '(' || escaped == ')' {
          buffer.push(escaped)
          index = index + 2
          continue
        }
      }
      buffer.push(ch)
      index = index + 1
      continue
    }
    if ch == ')' {
      return Ok(
        (String::from_array(buffer.view()), start.at(index + 1)),
      )
    }
    buffer.push(ch)
    index = index + 1
  }
  Err(start.error("unterminated (# ...) text node"))
}

///|
fn capture_attribute_value(start : Cursor) -> Result[(String, Cursor), String] {
  let buffer : Array[Char] = []
  let mut index = start.index
  while index < start.length() {
    let ch = start.char_at(index)
    if ch == '\\' {
      if index + 1 < start.length() {
        let escaped = start.char_at(index + 1)
        if escaped == '(' || escaped == ')' {
          buffer.push(escaped)
          index = index + 2
          continue
        }
      }
      buffer.push(ch)
      index = index + 1
      continue
    }
    if ch == '(' {
      return Err(
        start.at(index).error("attribute values must be plain text"),
      )
    }
    if ch == ')' {
      return Ok(
        (String::from_array(buffer.view()), start.at(index + 1)),
      )
    }
    buffer.push(ch)
    index = index + 1
  }
  Err(start.error("unterminated attribute"))
}

///|
fn upsert_attribute(
  attrs : Array[(String, String?)],
  name : String,
  value : String?,
) -> Unit {
  let mut index = 0
  while index < attrs.length() {
    match attrs[index] {
      (existing, _) if existing == name => {
        attrs[index] = (name, value)
        return
      }
      _ => index = index + 1
    }
  }
  attrs.push((name, value))
}

///|
fn append_parsed_nodes(target : Array[SexpNode], nodes : Array[(SexpNode, Bool)]) -> Unit {
  for parsed_node in nodes {
    match parsed_node {
      (node, _) => target.push(node)
    }
  }
}

///|
fn append_internal_nodes(
  target : Array[(SexpNode, Bool)],
  nodes : Array[(SexpNode, Bool)],
) -> Unit {
  for node in nodes {
    target.push(node)
  }
}

///|
fn parsed_node_values(nodes : Array[(SexpNode, Bool)]) -> Array[SexpNode] {
  let values : Array[SexpNode] = []
  append_parsed_nodes(values, nodes)
  values
}

///|
fn trim_trailing_text_before_attribute(children : Array[(SexpNode, Bool)]) -> Unit {
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

///|
fn error_at(index : Int, message : String) -> String {
  "parse error at offset " + index.to_string() + ": " + message
}
