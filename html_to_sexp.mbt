///|
pub fn html_to_sexp(source : String) -> Result[String, String] {
  let document = @html5.parse(source)
  render_html_fragment(document)
}

///|
fn render_html_fragment(document : @html5.Document) -> Result[String, String] {
  let terms : Array[String] = []
  let root_children = document.get_children(0)
  for node_id in root_children {
    match append_html_fragment_node(document, node_id, terms) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(terms.join("\n"))
}

///|
fn append_html_fragment_node(
  document : @html5.Document,
  node_id : Int,
  terms : Array[String],
) -> Result[Unit, String] {
  if node_id == document.document_element {
    return append_html_document_element(document, node_id, terms)
  }
  match render_html_node(document, node_id) {
    Ok(Some(term)) => {
      terms.push(term)
      Ok(())
    }
    Ok(None) => Ok(())
    Err(error) => Err(error)
  }
}

///|
fn append_html_document_element(
  document : @html5.Document,
  node_id : Int,
  terms : Array[String],
) -> Result[Unit, String] {
  match document.get_node(node_id) {
    Some(@html5.ElementNode(element)) => {
      for child_id in element.children {
        if child_id == document.head_element ||
          child_id == document.body_element {
          let children = document.get_children(child_id)
          for grandchild_id in children {
            match append_html_fragment_node(document, grandchild_id, terms) {
              Ok(_) => ()
              Err(error) => return Err(error)
            }
          }
        } else {
          match append_html_fragment_node(document, child_id, terms) {
            Ok(_) => ()
            Err(error) => return Err(error)
          }
        }
      }
      Ok(())
    }
    _ => Err("internal error: document root is not an html element")
  }
}

///|
fn render_html_node(
  document : @html5.Document,
  node_id : Int,
) -> Result[String?, String] {
  match document.get_node(node_id) {
    Some(@html5.TextNode(text)) => render_html_text_term(text)
    Some(@html5.CommentNode(text)) => Ok(Some(render_html_comment_term(text)))
    Some(@html5.ElementNode(element)) =>
      render_html_element_term(document, node_id, element)
    Some(@html5.DocumentTypeNode(..)) => Ok(None)
    Some(@html5.DocumentNode(children~))
    | Some(@html5.DocumentFragmentNode(children~)) =>
      render_html_node_list(document, children)
    None => Err("internal error: missing html node #" + node_id.to_string())
  }
}

///|
fn render_html_node_list(
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[String?, String] {
  let terms : Array[String] = []
  for node_id in node_ids {
    match render_html_node(document, node_id) {
      Ok(Some(term)) => terms.push(term)
      Ok(None) => ()
      Err(error) => return Err(error)
    }
  }
  if terms.is_empty() {
    Ok(None)
  } else {
    Ok(Some(terms.join("\n")))
  }
}

///|
fn render_html_text_term(text : String) -> Result[String?, String] {
  if text.is_blank() {
    return render_space_text_term(text)
  }
  let space_prefix = count_leading_spaces(text)
  if space_prefix == 0 {
    if starts_with_whitespace(text) {
      return Err(
        "unsupported html fragment: non-space leading whitespace cannot be represented: " +
        text,
      )
    }
    return Ok(Some(escape_sexp_text(text)))
  }
  let remainder = text.sub(start=space_prefix).to_owned()
  if remainder.is_empty() {
    return Ok(Some(render_space_forms(space_prefix)))
  }
  if starts_with_whitespace(remainder) {
    return Err(
      "unsupported html fragment: non-space leading whitespace cannot be represented: " +
      text,
    )
  }
  Ok(Some(render_space_forms(space_prefix) + " " + escape_sexp_text(remainder)))
}

///|
fn render_html_comment_term(text : String) -> String {
  let normalized = if text.is_blank() { "" } else { text.trim().to_owned() }
  if normalized.is_empty() {
    "(% )"
  } else {
    "(% " + escape_sexp_text(normalized) + ")"
  }
}

///|
fn render_html_element_term(
  document : @html5.Document,
  node_id : Int,
  element : @html5.Element,
) -> Result[String?, String] {
  let builder = StringBuilder::new()
  builder.write_char('(')
  builder.write_string(element.tag_name)
  for attr in element.attributes {
    let (name, value) = attr
    builder.write_char(' ')
    match render_html_attribute(name, value) {
      Ok(attr_term) => builder.write_string(attr_term)
      Err(error) => return Err(error)
    }
  }
  let child_terms : Array[String] = []
  let child_ids = match document.get_template_content(node_id) {
    id if id != @html5.NO_NODE => document.get_children(id)
    _ => element.children
  }
  for child_id in child_ids {
    match render_html_node(document, child_id) {
      Ok(Some(term)) => child_terms.push(term)
      Ok(None) => ()
      Err(error) => return Err(error)
    }
  }
  for term in child_terms {
    builder.write_char(' ')
    builder.write_string(term)
  }
  builder.write_char(')')
  Ok(Some(builder.to_string()))
}

///|
fn render_html_attribute(
  name : String,
  value : String,
) -> Result[String, String] {
  if value.is_empty() {
    return Ok("(:" + name + ")")
  }
  if starts_with_whitespace(value) {
    return Err(
      "unsupported html attribute: leading whitespace value on " + name,
    )
  }
  Ok("(:" + name + " " + escape_sexp_text(value) + ")")
}

///|
fn starts_with_whitespace(text : String) -> Bool {
  match text.get_char(0) {
    Some(ch) => ch.is_whitespace()
    None => false
  }
}

///|
fn count_leading_spaces(text : String) -> Int {
  let chars = text.to_array()
  let mut index = 0
  while index < chars.length() && chars[index] == ' ' {
    index = index + 1
  }
  index
}

///|
fn render_space_text_term(text : String) -> Result[String?, String] {
  let space_count = count_leading_spaces(text)
  if space_count == text.length() {
    return Ok(Some(render_space_forms(space_count)))
  }
  Err(
    "unsupported html fragment: whitespace-only text nodes with non-space characters cannot be represented: " +
    text,
  )
}

///|
fn render_space_forms(count : Int) -> String {
  let parts : Array[String] = []
  let mut index = 0
  while index < count {
    parts.push("(~)")
    index = index + 1
  }
  parts.join(" ")
}

///|
fn escape_sexp_text(text : String) -> String {
  let chars = text.to_array()
  let builder = StringBuilder::new()
  let mut index = 0
  while index < chars.length() {
    let ch = chars[index]
    if ch == '\\' {
      if index + 1 < chars.length() {
        let next = chars[index + 1]
        if next == '(' || next == ')' {
          builder.write_char('\\')
        }
      }
      builder.write_char(ch)
    } else if ch == '(' || ch == ')' {
      builder.write_char('\\')
      builder.write_char(ch)
    } else {
      builder.write_char(ch)
    }
    index = index + 1
  }
  builder.to_string()
}
