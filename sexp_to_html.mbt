///|
pub fn sexp_to_html(source : String) -> Result[String, String] {
  let chars = source.to_array()
  match parse_document(chars) {
    Ok(nodes) => Ok(render_document(nodes))
    Err(error) => Err(error)
  }
}

///|
priv enum Node {
  Text(String)
  Space
  Comment(String)
  Element(String, Array[(String, String?)], Array[Node])
  SpacedElement(String, Array[(String, String?)], Array[Node])
}

///|
priv enum ParsedListItem {
  Attr(String, String?)
  Node(Node)
}

///|
fn parse_document(chars : Array[Char]) -> Result[Array[Node], String] {
  let nodes : Array[Node] = []
  let mut index = skip_whitespace(chars, 0)
  while index < chars.length() {
    if chars[index] == ')' {
      return Err(error_at(index, "unexpected ')'"))
    }
    match parse_node(chars, index) {
      Ok((node, next)) => {
        nodes.push(node)
        index = skip_whitespace(chars, next)
      }
      Err(error) => return Err(error)
    }
  }
  Ok(nodes)
}

///|
fn parse_node(chars : Array[Char], index : Int) -> Result[(Node, Int), String] {
  if index >= chars.length() {
    return Err(error_at(index, "unexpected end of input"))
  }
  if chars[index] == '(' {
    match parse_list_item(chars, index) {
      Ok((Node(node), next)) => Ok((node, next))
      Ok((Attr(_, _), _)) =>
        Err(error_at(index, "attribute cannot appear at the document root"))
      Err(error) => Err(error)
    }
  } else if chars[index] == ')' {
    Err(error_at(index, "unexpected ')'"))
  } else {
    let (text, next) = parse_text(chars, index)
    Ok((Text(text), next))
  }
}

///|
fn parse_list_item(
  chars : Array[Char],
  open_index : Int,
) -> Result[(ParsedListItem, Int), String] {
  let mut index = open_index + 1
  index = skip_whitespace(chars, index)
  if index >= chars.length() {
    return Err(error_at(open_index, "unterminated list"))
  }
  if chars[index] == ')' {
    return Err(error_at(open_index, "empty list is invalid"))
  }
  let (head, next) = parse_head(chars, index)
  if head == "%" {
    parse_comment(chars, next)
  } else if head == "#" {
    parse_raw_text(chars, next)
  } else if head == "~" {
    parse_space(chars, next)
  } else if head.has_prefix("~") {
    parse_spaced_element(chars, head, next)
  } else if head.has_prefix(":") {
    parse_attribute(chars, head, next)
  } else {
    parse_element(chars, head, next)
  }
}

///|
fn parse_comment(
  chars : Array[Char],
  after_head : Int,
) -> Result[(ParsedListItem, Int), String] {
  let start = skip_whitespace(chars, after_head)
  match capture_comment_text(chars, start) {
    Ok((content, next)) => Ok((Node(Comment(content)), next))
    Err(error) => Err(error)
  }
}

///|
fn parse_raw_text(
  chars : Array[Char],
  after_head : Int,
) -> Result[(ParsedListItem, Int), String] {
  let start = if after_head < chars.length() &&
    chars[after_head].is_whitespace() {
    after_head + 1
  } else {
    after_head
  }
  match capture_raw_text(chars, start) {
    Ok((content, next)) => Ok((Node(Text(content)), next))
    Err(error) => Err(error)
  }
}

///|
fn parse_space(
  chars : Array[Char],
  after_head : Int,
) -> Result[(ParsedListItem, Int), String] {
  let index = skip_whitespace(chars, after_head)
  if index >= chars.length() {
    return Err(error_at(after_head, "unterminated (~) form"))
  }
  if chars[index] != ')' {
    return Err(error_at(index, "(~) cannot contain attributes or children"))
  }
  Ok((Node(Space), index + 1))
}

///|
fn parse_spaced_element(
  chars : Array[Char],
  head : String,
  after_head : Int,
) -> Result[(ParsedListItem, Int), String] {
  let tag = head.sub(start=1).to_owned()
  if tag.is_empty() {
    return Err(error_at(after_head, "empty ~ tag must use the exact form (~)"))
  }
  parse_element_with_kind(chars, tag, after_head, true)
}

///|
fn parse_attribute(
  chars : Array[Char],
  head : String,
  after_head : Int,
) -> Result[(ParsedListItem, Int), String] {
  if head.length() <= 1 {
    return Err(error_at(after_head, "attribute name cannot be empty"))
  }
  let name = head.sub(start=1).to_owned()
  let index = skip_whitespace(chars, after_head)
  if index >= chars.length() {
    return Err(error_at(after_head, "unterminated attribute"))
  }
  if chars[index] == ')' {
    return Ok((Attr(name, None), index + 1))
  }
  match capture_attribute_value(chars, index) {
    Ok((value, next)) => Ok((Attr(name, Some(value)), next))
    Err(error) => Err(error)
  }
}

///|
fn parse_element(
  chars : Array[Char],
  tag : String,
  after_head : Int,
) -> Result[(ParsedListItem, Int), String] {
  parse_element_with_kind(chars, tag, after_head, false)
}

///|
fn parse_element_with_kind(
  chars : Array[Char],
  tag : String,
  after_head : Int,
  spaced : Bool,
) -> Result[(ParsedListItem, Int), String] {
  let attrs : Array[(String, String?)] = []
  let children : Array[Node] = []
  let mut index = skip_whitespace(chars, after_head)
  while index < chars.length() {
    if chars[index] == ')' {
      if is_void_tag(tag) && !children.is_empty() {
        return Err(
          error_at(index, "void element <" + tag + "> cannot have child nodes"),
        )
      }
      let node = if spaced {
        SpacedElement(tag, attrs, children)
      } else {
        Element(tag, attrs, children)
      }
      return Ok((Node(node), index + 1))
    }
    if chars[index] == '(' {
      match parse_list_item(chars, index) {
        Ok((Attr(name, value), next)) => {
          trim_trailing_text_before_attribute(children)
          upsert_attribute(attrs, name, value)
          index = skip_whitespace(chars, next)
        }
        Ok((Node(node), next)) => {
          children.push(node)
          index = skip_whitespace(chars, next)
        }
        Err(error) => return Err(error)
      }
    } else {
      let (text, next) = parse_text(chars, index)
      if !text.is_empty() {
        children.push(Text(text))
      }
      index = skip_whitespace(chars, next)
    }
  }
  Err(error_at(after_head, "unterminated element <" + tag + ">"))
}

///|
fn parse_head(chars : Array[Char], start : Int) -> (String, Int) {
  let mut index = start
  while index < chars.length() {
    let ch = chars[index]
    if ch == '(' || ch == ')' || ch.is_whitespace() {
      break
    }
    index = index + 1
  }
  (String::from_array(chars.view(start~, end=index)), index)
}

///|
fn parse_text(chars : Array[Char], start : Int) -> (String, Int) {
  let buffer : Array[Char] = []
  let mut index = start
  while index < chars.length() {
    let ch = chars[index]
    if ch == '\\' {
      if index + 1 < chars.length() {
        let escaped = chars[index + 1]
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
  (String::from_array(buffer.view()), index)
}

///|
fn capture_comment_text(
  chars : Array[Char],
  start : Int,
) -> Result[(String, Int), String] {
  let buffer : Array[Char] = []
  let mut index = start
  let mut depth = 0
  while index < chars.length() {
    let ch = chars[index]
    if ch == '\\' {
      if index + 1 < chars.length() {
        let escaped = chars[index + 1]
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
        return Ok((String::from_array(buffer.view()), index + 1))
      }
      depth = depth - 1
      buffer.push(ch)
      index = index + 1
      continue
    }
    buffer.push(ch)
    index = index + 1
  }
  Err(error_at(start, "unterminated comment"))
}

///|
fn capture_raw_text(
  chars : Array[Char],
  start : Int,
) -> Result[(String, Int), String] {
  let buffer : Array[Char] = []
  let mut index = start
  while index < chars.length() {
    let ch = chars[index]
    if ch == '\\' {
      if index + 1 < chars.length() {
        let escaped = chars[index + 1]
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
      return Ok((String::from_array(buffer.view()), index + 1))
    }
    buffer.push(ch)
    index = index + 1
  }
  Err(error_at(start, "unterminated (# ...) text node"))
}

///|
fn capture_attribute_value(
  chars : Array[Char],
  start : Int,
) -> Result[(String, Int), String] {
  let buffer : Array[Char] = []
  let mut index = start
  while index < chars.length() {
    let ch = chars[index]
    if ch == '\\' {
      if index + 1 < chars.length() {
        let escaped = chars[index + 1]
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
      return Err(error_at(index, "attribute values must be plain text"))
    }
    if ch == ')' {
      return Ok((String::from_array(buffer.view()), index + 1))
    }
    buffer.push(ch)
    index = index + 1
  }
  Err(error_at(start, "unterminated attribute"))
}

///|
fn skip_whitespace(chars : Array[Char], start : Int) -> Int {
  let mut index = start
  while index < chars.length() && chars[index].is_whitespace() {
    index = index + 1
  }
  index
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
fn trim_trailing_text_before_attribute(children : Array[Node]) -> Unit {
  if children.is_empty() {
    return
  }
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

///|
fn render_document(nodes : Array[Node]) -> String {
  let parts : Array[String] = []
  let mut index = 0
  while index < nodes.length() {
    parts.push(render_node(nodes[index]))
    index = index + 1
  }
  parts.join("")
}

///|
fn render_node(node : Node) -> String {
  match node {
    Text(text) => escape_text(text)
    Space => " "
    Comment(text) => "<!-- " + text + " -->"
    Element(tag, attrs, children) => render_element(tag, attrs, children)
    SpacedElement(tag, attrs, children) =>
      " " + render_element(tag, attrs, children) + " "
  }
}

///|
fn render_element(
  tag : String,
  attrs : Array[(String, String?)],
  children : Array[Node],
) -> String {
  let parts : Array[String] = ["<", tag]
  let mut index = 0
  while index < attrs.length() {
    match attrs[index] {
      (name, None) => {
        parts.push(" ")
        parts.push(name)
      }
      (name, Some(value)) => {
        parts.push(" ")
        parts.push(name)
        parts.push("=\"")
        parts.push(escape_attribute_value(value))
        parts.push("\"")
      }
    }
    index = index + 1
  }
  parts.push(">")
  if is_void_tag(tag) {
    return parts.join("")
  }
  index = 0
  while index < children.length() {
    parts.push(render_node(children[index]))
    index = index + 1
  }
  parts.push("</")
  parts.push(tag)
  parts.push(">")
  parts.join("")
}

///|
fn escape_text(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
fn escape_attribute_value(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
}

///|
fn is_void_tag(tag : String) -> Bool {
  let lower = tag.to_lower()
  lower == "area" ||
  lower == "base" ||
  lower == "br" ||
  lower == "col" ||
  lower == "embed" ||
  lower == "hr" ||
  lower == "img" ||
  lower == "input" ||
  lower == "link" ||
  lower == "meta" ||
  lower == "param" ||
  lower == "source" ||
  lower == "track" ||
  lower == "wbr"
}

///|
fn error_at(index : Int, message : String) -> String {
  "parse error at offset " + index.to_string() + ": " + message
}
