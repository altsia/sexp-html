///|
pub(all) enum SexpNode {
  Text(String)
  Comment(String)
  RawHtml(String)
  Element(String, Array[(String, String?)], Array[SexpNode])
}

///|
pub type NodeWithTrimBeforeAttr = (SexpNode, Bool)

///|
pub enum ParsedListForm {
  Attr(String, String?)
  Nodes(Array[NodeWithTrimBeforeAttr])
}

///|
pub enum ParsedHead {
  CommentHead
  RawTextHead
  SpaceHead
  SpacedElementHead(String)
  AttributeHead(String)
  ElementHead(String)
}

///| Parses a full S-expression HTML fragment into normalized AST nodes.
pub fn parse_sexp_html(source : String) -> Result[Array[SexpNode], String] {
  parse_document(Cursor::new(source))
}

///| Parses top-level nodes, where attributes are not valid and whitespace only
///| separates neighboring terms.
fn parse_document(start : Cursor) -> Result[Array[SexpNode], String] {
  let nodes : Array[SexpNode] = []
  let mut cursor = start.skip_whitespace()
  while !cursor.is_end() {
    if cursor.peek() == Some(')') {
      return Err(cursor.error("unexpected ')'"))
    }
    match parse_node(cursor) {
      Ok((parsed_nodes, next)) => {
        append_node_values(nodes, parsed_nodes)
        cursor = next.skip_whitespace()
      }
      Err(error) => return Err(error)
    }
  }
  Ok(nodes)
}

///| Parses one root/child item. Text nodes carry a trim flag so later attribute
///| forms can remove separator whitespace that belonged to syntax, not content.
fn parse_node(
  cursor : Cursor,
) -> Result[(Array[(SexpNode, Bool)], Cursor), String] {
  match cursor.peek() {
    None => Err(cursor.error("unexpected end of input"))
    Some('(') =>
      parse_list_form(cursor).bind(item => {
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

///| Reads the list head and dispatches the rest of the list to the matching
///| payload parser.
fn parse_list_form(open : Cursor) -> Result[(ParsedListForm, Cursor), String] {
  parse_list_form_head(open).bind(ParsedHead::parse_payload_pair)
}

///|
fn parse_list_form_head(open : Cursor) -> Result[(ParsedHead, Cursor), String] {
  let head_start = open.advance_code_units(1).skip_whitespace()
  match head_start.peek() {
    None => return Err(open.error("unterminated list"))
    Some(')') => return Err(open.error("empty list is invalid"))
    _ => ()
  }

  let (head, after_head) = parse_head(head_start)
  if head.is_empty() {
    return Err(head_start.error("list head cannot be empty"))
  }
  ParsedHead::parse(head, after_head.index).map(parsed_head => {
    (parsed_head, after_head)
  })
}

///| Classifies a head token into syntax forms: %, #, ~, ~tag, :attr, or element.
fn ParsedHead::parse(
  head : String,
  after_head : Int,
) -> Result[ParsedHead, String] {
  match head {
    "%" => Ok(CommentHead)
    "#" => Ok(RawTextHead)
    "~" => Ok(SpaceHead)
    _ if head.has_prefix("~") =>
      ParsedHead::parse_spaced_element(head, after_head)
    _ if head.has_prefix(":") => ParsedHead::parse_attribute(head, after_head)
    _ => Ok(ElementHead(head))
  }
}

///|
fn ParsedHead::parse_spaced_element(
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
fn ParsedHead::parse_attribute(
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
fn ParsedHead::parse_payload_pair(
  data : (ParsedHead, Cursor),
) -> Result[(ParsedListForm, Cursor), String] {
  data.0.parse_payload(data.1)
}

///|
fn ParsedHead::parse_payload(
  head : ParsedHead,
  after_head : Cursor,
) -> Result[(ParsedListForm, Cursor), String] {
  match head {
    CommentHead => parse_comment(after_head)
    RawTextHead => parse_raw_text(after_head)
    SpaceHead => parse_space(after_head)
    SpacedElementHead(tag) => parse_element_with_spacing(after_head, tag, true)
    AttributeHead(name) => parse_attribute(after_head, name)
    ElementHead(tag) => parse_element(after_head, tag)
  }
}

///| Parses `(% payload)`. Separator whitespace after `%` is not comment content;
///| the payload parser then keeps balanced parentheses until the closing list paren.
fn parse_comment(
  after_head : Cursor,
) -> Result[(ParsedListForm, Cursor), String] {
  let start = after_head.skip_whitespace()
  parse_comment_payload(start).map(result => {
    let (content, next) = result
    (Nodes([(Comment(content), false)]), next)
  })
}

///| Parses `(# payload)`. At most one whitespace char after `#` is syntax
///| separator; any further whitespace is literal raw text.
fn parse_raw_text(
  after_head : Cursor,
) -> Result[(ParsedListForm, Cursor), String] {
  let start = if after_head.peek().map_or(false, ch => ch.is_whitespace()) {
    after_head.advance_code_units(1)
  } else {
    after_head
  }
  parse_raw_text_payload(start).map(result => {
    let (content, next) = result
    (Nodes([(Text(content), false)]), next)
  })
}

///| Parses `(~)`, the explicit single-space node. Other payload is rejected so
///| `~tag` remains the only spaced element form.
fn parse_space(after_head : Cursor) -> Result[(ParsedListForm, Cursor), String] {
  let cursor = after_head.skip_whitespace()
  match cursor.peek() {
    None => Err(after_head.error("unterminated (~) form"))
    Some(')') => Ok((Nodes([(Text(" "), false)]), cursor.advance_code_units(1)))
    _ => Err(cursor.error("(~) cannot contain attributes or children"))
  }
}

///| Parses `(:name)` and `(:name value)`. Attribute values are plain text only;
///| nested list structure is intentionally rejected by the payload scanner.
fn parse_attribute(
  after_head : Cursor,
  name : String,
) -> Result[(ParsedListForm, Cursor), String] {
  let cursor = after_head.skip_whitespace()
  match cursor.peek() {
    None => Err(after_head.error("unterminated attribute"))
    Some(')') => Ok((Attr(name, None), cursor.advance_code_units(1)))
    _ =>
      parse_attribute_value_payload(cursor).map(result => {
        let (value, next) = result
        (Attr(name, Some(value)), next)
      })
  }
}

///|
fn parse_element(
  after_head : Cursor,
  tag : String,
) -> Result[(ParsedListForm, Cursor), String] {
  parse_element_with_spacing(after_head, tag, false)
}

///| Parses an element body, collecting attributes and children in source order.
///| Attribute forms may appear after children; the final AST stores attributes on
///| the element and trims separator text that preceded those late attributes.
fn parse_element_with_spacing(
  after_head : Cursor,
  tag : String,
  spaced : Bool,
) -> Result[(ParsedListForm, Cursor), String] {
  let attrs : Array[(String, String?)] = []
  let children : Array[(SexpNode, Bool)] = []
  let mut cursor = after_head.skip_whitespace()
  while !cursor.is_end() {
    match cursor.peek() {
      Some(')') =>
        return build_element_result(tag, attrs, children, spaced, cursor)
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

///| Builds the element result after the closing paren, applying void-element and
///| `~tag` spacing rules at the boundary where all children are known.
fn build_element_result(
  tag : String,
  attrs : Array[(String, String?)],
  children : Array[(SexpNode, Bool)],
  spaced : Bool,
  close : Cursor,
) -> Result[(ParsedListForm, Cursor), String] {
  if is_void_element_name(tag) && !children.is_empty() {
    return Err(
      close.error("void element <" + tag + "> cannot have child nodes"),
    )
  }
  let element = Element(tag, attrs, strip_parse_flags(children))
  guard spaced else {
    Ok((Nodes([(element, false)]), close.advance_code_units(1)))
  }
  Ok(
    (
      Nodes([(Text(" "), false), (element, false), (Text(" "), false)]),
      close.advance_code_units(1),
    ),
  )
}

///| Handles one parenthesized item inside an element, either merging an attribute
///| into the element attrs or appending child nodes.
fn parse_element_list_item(
  cursor : Cursor,
  attrs : Array[(String, String?)],
  children : Array[(SexpNode, Bool)],
) -> Result[Cursor, String] {
  parse_list_form(cursor).bind(item => {
    match item {
      (Attr(name, value), next) => {
        trim_trailing_text_before_attribute(children)
        HtmlAttrs::upsert(attrs, name, value)
        Ok(next)
      }
      (Nodes(nodes), next) => {
        append_parsed_child_nodes(children, nodes)
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

///| Reads an unparenthesized head token up to whitespace or a list boundary.
fn parse_head(start : Cursor) -> (String, Cursor) {
  let mut index = start.index
  while index < start.code_unit_length() {
    let ch = start.unsafe_char_at(index)
    if ch == '(' || ch == ')' || ch.is_whitespace() {
      break
    }
    index = start.next_char_index(index)
  }
  (start.slice_until(index), start.with_index(index))
}

///| Payload scanning modes share escaping but differ in how unescaped parens end
///| or invalidate the payload.
priv enum PayloadScanMode {
  CommentPayload
  RawTextPayload
  AttributeValuePayload
}

///| Parses ordinary text until an unescaped list boundary. Only `\(` and `\)`
///| are unescaped; other backslashes remain literal text.
fn parse_text(start : Cursor) -> (String, Cursor) {
  let buffer : Array[Char] = []
  let mut index = start.index
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
    } else if ch == '(' || ch == ')' {
      break
    }
    buffer.push(ch)
    index = start.next_char_index(index)
  }
  (text_from_buffer(buffer), start.with_index(index))
}

///| Parses comment payload text, allowing balanced unescaped parentheses inside
///| the comment until the list's closing paren is reached.
fn parse_comment_payload(start : Cursor) -> Result[(String, Cursor), String] {
  scan_payload(start, CommentPayload)
}

///| Parses raw text payload up to the first unescaped closing paren.
fn parse_raw_text_payload(start : Cursor) -> Result[(String, Cursor), String] {
  scan_payload(start, RawTextPayload)
}

///| Parses an attribute value payload; values may contain escaped parens but not
///| unescaped nested list structure.
fn parse_attribute_value_payload(
  start : Cursor,
) -> Result[(String, Cursor), String] {
  scan_payload(start, AttributeValuePayload)
}

///| Shared payload scanner for delimited text forms. It centralizes `\(`/`\)`
///| handling while keeping each syntax form's paren rules explicit in `mode`.
fn scan_payload(
  start : Cursor,
  mode : PayloadScanMode,
) -> Result[(String, Cursor), String] {
  let buffer : Array[Char] = []
  let mut index = start.index
  let mut comment_depth = 0
  while index < start.code_unit_length() {
    let ch = start.unsafe_char_at(index)
    match ch {
      '\\' =>
        if consume_escaped_paren_into(start, index, buffer) is Some(next) {
          index = next
          continue
        }
      '(' =>
        match mode {
          CommentPayload => comment_depth = comment_depth + 1
          AttributeValuePayload =>
            return Err(
              start
              .with_index(index)
              .error("attribute values must be plain text"),
            )
          RawTextPayload => ()
        }
      ')' =>
        match mode {
          CommentPayload => {
            guard comment_depth == 0 else { comment_depth = comment_depth - 1 }
            return Ok((text_from_buffer(buffer), start.with_index(index + 1)))
          }
          RawTextPayload | AttributeValuePayload =>
            return Ok((text_from_buffer(buffer), start.with_index(index + 1)))
        }
      _ => ()
    }
    buffer.push(ch)
    index = start.next_char_index(index)
  }
  Err(start.error(mode.unterminated_message()))
}

///| Returns the EOF error text for each delimited payload form.
fn PayloadScanMode::unterminated_message(self : PayloadScanMode) -> String {
  match self {
    CommentPayload => "unterminated comment"
    RawTextPayload => "unterminated (# ...) text node"
    AttributeValuePayload => "unterminated attribute"
  }
}

///|
fn text_from_buffer(buffer : Array[Char]) -> String {
  String::from_array(buffer.view())
}

///| Consumes `\(` or `\)` as a literal paren and returns the next code-unit
///| index. Other backslashes are left for the caller to copy unchanged.
fn consume_escaped_paren_into(
  source : Cursor,
  index : Int,
  buffer : Array[Char],
) -> Int? {
  guard index + 1 < source.code_unit_length() else { return None }
  let escaped = source.unsafe_char_at(index + 1)
  guard escaped == '(' || escaped == ')' else { return None }
  buffer.push(escaped)
  Some(index + 2)
}

///|
fn append_node_values(
  target : Array[SexpNode],
  nodes : Array[(SexpNode, Bool)],
) -> Unit {
  target.append(strip_parse_flags(nodes))
}

///|
fn append_parsed_child_nodes(
  target : Array[(SexpNode, Bool)],
  nodes : Array[(SexpNode, Bool)],
) -> Unit {
  target.append(nodes)
}

///| Removes parser-only trim flags once the caller no longer needs to distinguish
///| syntactic separator text from literal text.
fn strip_parse_flags(nodes : Array[NodeWithTrimBeforeAttr]) -> Array[SexpNode] {
  nodes.map(pair => pair.0)
}

///| If an attribute appears after text, trim or remove the immediately preceding
///| text node when it only carried separator whitespace before that attribute.
fn trim_trailing_text_before_attribute(
  children : Array[(SexpNode, Bool)],
) -> Unit {
  guard !children.is_empty() else { return }
  let last_index = children.length() - 1
  guard children[last_index] is (Text(text), true) else {  }
  let trimmed = text.trim_end().to_owned()
  guard trimmed.is_empty() else { children[last_index] = (Text(trimmed), true) }
  children.truncate(last_index)
}
