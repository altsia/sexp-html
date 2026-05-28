///|
pub fn html_to_sexp(source : String) -> Result[String, String] {
  let document = @html5.parse(source)
  render_html_fragment(document)
}

///|
fn render_html_fragment(document : @html5.Document) -> Result[String, String] {
  render_html_fragment_terms(document, document.get_children(0)).map(terms => {
    terms.join("\n")
  })
}

///|
fn render_html_fragment_terms(
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Array[String], String] {
  let terms : Array[String] = []
  append_html_fragment_terms(document, terms, node_ids).map(_ => terms)
}

///|
fn render_html_fragment_node_terms(
  document : @html5.Document,
  node_id : Int,
) -> Result[Array[String], String] {
  if node_id == document.document_element {
    return render_html_document_element_terms(document, node_id)
  }
  render_html_node(document, node_id).map(optional_term_to_terms)
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
        match
          append_html_fragment_terms(
            document,
            terms,
            html_document_fragment_child_ids(document, child_id),
          ) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      Ok(terms)
    }
    _ => Err("internal error: document root is not an html element")
  }
}

///|
fn append_html_fragment_terms(
  document : @html5.Document,
  terms : Array[String],
  node_ids : Array[Int],
) -> Result[Unit, String] {
  for node_id in node_ids {
    match render_html_fragment_node_terms(document, node_id) {
      Ok(node_terms) => append_terms(terms, node_terms)
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn html_document_fragment_child_ids(
  document : @html5.Document,
  child_id : Int,
) -> Array[Int] {
  if child_id == document.head_element || child_id == document.body_element {
    document.get_children(child_id)
  } else {
    [child_id]
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
  collect_rendered_html_terms(document, node_ids).map(join_non_empty_terms)
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
  match append_rendered_html_attributes(builder, element.attributes) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match
    append_rendered_child_terms(
      builder,
      document,
      html_element_child_ids(document, node_id, element),
    ) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  builder.write_char(')')
  Ok(Some(builder.to_string()))
}

///|
fn append_rendered_html_attributes(
  builder : StringBuilder,
  attrs : Array[(String, String)],
) -> Result[Unit, String] {
  for attr in attrs {
    let (name, value) = attr
    builder.write_char(' ')
    match render_html_attribute(name, value) {
      Ok(attr_term) => builder.write_string(attr_term)
      Err(error) => return Err(error)
    }
  }
  Ok(())
}

///|
fn append_rendered_child_terms(
  builder : StringBuilder,
  document : @html5.Document,
  node_ids : Array[Int],
) -> Result[Unit, String] {
  collect_rendered_html_terms(document, node_ids).map(child_terms => {
    for term in child_terms {
      builder.write_char(' ')
      builder.write_string(term)
    }
  })
}

///|
fn html_element_child_ids(
  document : @html5.Document,
  node_id : Int,
  element : @html5.Element,
) -> Array[Int] {
  match document.get_template_content(node_id) {
    id if id != @html5.NO_NODE => document.get_children(id)
    _ => element.children
  }
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
  target.append(terms)
}

///|
fn starts_with_whitespace(text : String) -> Bool {
  text.get_char(0).map_or(false, ch => ch.is_whitespace())
}

///|
fn render_raw_text_form(text : String) -> String {
  "(# " + escape_sexp_text(text) + ")"
}

///|
fn optional_term_to_terms(term : String?) -> Array[String] {
  match term {
    Some(term) => [term]
    None => []
  }
}

///|
fn join_non_empty_terms(terms : Array[String]) -> String? {
  if terms.is_empty() {
    None
  } else {
    Some(terms.join("\n"))
  }
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
