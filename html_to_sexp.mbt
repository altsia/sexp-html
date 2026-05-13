///|
pub fn html_to_sexp(source : String) -> Result[String, String] {
  let document = @html5.parse(source)
  render_html_fragment(document)
}

///|
fn render_html_fragment(document : @html5.Document) -> Result[String, String] {
  render_html_fragment_terms(document, document.get_children(0)).map(fn(terms) {
    terms.join("\n")
  })
}

///|
fn render_html_fragment_terms(
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Array[String], String] {
  let terms : Array[String] = []
  for node_id in node_ids {
    match render_html_fragment_node_terms(document, node_id) {
      Ok(node_terms) => append_terms(terms, node_terms)
      Err(error) => return Err(error)
    }
  }
  Ok(terms)
}

///|
fn render_html_fragment_node_terms(
  document : @html5.Document,
  node_id : Int,
) -> Result[Array[String], String] {
  if node_id == document.document_element {
    return render_html_document_element_terms(document, node_id)
  }
  render_html_node(document, node_id).map(fn(term) {
    match term {
      Some(term) => [term]
      None => []
    }
  })
}

///|
fn render_html_document_element_terms(
  document : @html5.Document,
  node_id : Int,
) -> Result[Array[String], String] {
  match document.get_node(node_id) {
    Some(@html5.ElementNode(element)) => {
      let terms : Array[String] = []
      for child_id in element.children {
        let nested_ids = if child_id == document.head_element ||
          child_id == document.body_element {
          document.get_children(child_id)
        } else {
          [child_id]
        }
        match render_html_fragment_terms(document, nested_ids) {
          Ok(child_terms) => append_terms(terms, child_terms)
          Err(error) => return Err(error)
        }
      }
      Ok(terms)
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
  let terms = match collect_rendered_html_terms(document, node_ids) {
    Ok(terms) => terms
    Err(error) => return Err(error)
  }
  if terms.is_empty() {
    Ok(None)
  } else {
    Ok(Some(terms.join("\n")))
  }
}

///|
fn render_html_text_term(text : String) -> Result[String?, String] {
  if !text.is_empty() && !starts_with_whitespace(text) {
    return Ok(Some(escape_sexp_text(text)))
  }
  Ok(Some(render_raw_text_form(text)))
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
  let child_ids = match document.get_template_content(node_id) {
    id if id != @html5.NO_NODE => document.get_children(id)
    _ => element.children
  }
  let child_terms = match collect_rendered_html_terms(document, child_ids) {
    Ok(terms) => terms
    Err(error) => return Err(error)
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
fn collect_rendered_html_terms(
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Array[String], String] {
  let terms : Array[String] = []
  for node_id in node_ids {
    match render_html_node(document, node_id) {
      Ok(Some(term)) => terms.push(term)
      Ok(None) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(terms)
}

///|
fn append_terms(target : Array[String], terms : Array[String]) -> Unit {
  for term in terms {
    target.push(term)
  }
}

///|
fn starts_with_whitespace(text : String) -> Bool {
  match text.get_char(0) {
    Some(ch) => ch.is_whitespace()
    None => false
  }
}

///|
fn render_raw_text_form(text : String) -> String {
  "(# " + escape_sexp_text(text) + ")"
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
